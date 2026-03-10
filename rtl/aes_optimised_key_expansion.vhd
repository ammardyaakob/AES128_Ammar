----------------------------------------------------------------------------------
-- Company: University of Sheffield
-- Engineer: David Cracknell
--
-- Create Date: 02/03/2026 01:41:15 PM
-- Design Name:
-- Module Name: aes_key_expansion - Behavioral
-- Project Name: optimised for low area AES device
-- Description:
--   Serial AES-128 key expansion.
--   The encrypt-only build keeps just the current 128-bit round key plus the
--   4-byte g() cache. Round transitions are computed a word at a time instead
--   of updating all 16 bytes through a wider byte-indexed datapath, reducing
--   control/mux area while preserving the streamed round-key interface.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity aes_key_expansion is
    generic(
        support_decrypt : boolean := true
    );
    port(
        clk     : in  std_logic;
        rst     : in  std_logic;
        start   : in  std_logic;
        encrypt : in  std_logic;
        key_in  : in  std_logic_vector(127 downto 0);

        roundkey_byte_out : out std_logic_vector(7 downto 0);
        roundkey_valid    : out std_logic;

        round_idx_out     : out std_logic_vector(3 downto 0);
        byte_idx_out      : out std_logic_vector(3 downto 0);

        roundkey_block_out   : out std_logic_vector(127 downto 0);
        roundkey_block_valid : out std_logic;
        last_roundkey_out    : out std_logic_vector(127 downto 0);

        busy : out std_logic;
        done : out std_logic
    );
end entity aes_key_expansion;

architecture rtl of aes_key_expansion is

    subtype byte_t is std_logic_vector(7 downto 0);
    subtype word_t is std_logic_vector(31 downto 0);
    type word_array4_t is array (0 to 3) of word_t;
    type byte_array4_t is array (0 to 3) of byte_t;

    type rcon_array_t is array (1 to 10) of byte_t;
    constant RCON_B : rcon_array_t := (
        x"01", x"02", x"04", x"08", x"10",
        x"20", x"40", x"80", x"1B", x"36"
    );

    constant ROUND_0_C  : unsigned(3 downto 0) := (others => '0');
    constant ROUND_9_C  : unsigned(3 downto 0) := to_unsigned(9, 4);
    constant ROUND_10_C : unsigned(3 downto 0) := to_unsigned(10, 4);
    constant IDX_LAST_C : unsigned(1 downto 0) := to_unsigned(3, 2);

    function unpack_key_words(
        key_value : std_logic_vector(127 downto 0)
    ) return word_array4_t is
        variable result : word_array4_t;
    begin
        for i in 0 to 3 loop
            result(i) := key_value(127 - i*32 downto 96 - i*32);
        end loop;
        return result;
    end function;

    function word_byte(
        word_value : word_t;
        idx        : natural
    ) return byte_t is
    begin
        case idx is
            when 0      => return word_value(31 downto 24);
            when 1      => return word_value(23 downto 16);
            when 2      => return word_value(15 downto 8);
            when others => return word_value(7 downto 0);
        end case;
    end function;

    function rotword_byte(
        word_value : word_t;
        idx        : natural
    ) return byte_t is
    begin
        case idx is
            when 0      => return word_value(23 downto 16);
            when 1      => return word_value(15 downto 8);
            when 2      => return word_value(7 downto 0);
            when others => return word_value(31 downto 24);
        end case;
    end function;

    function pack_g_word(
        g_bytes : byte_array4_t
    ) return word_t is
    begin
        return g_bytes(0) & g_bytes(1) & g_bytes(2) & g_bytes(3);
    end function;

    function next_round_words(
        curr_words : word_array4_t;
        g_bytes    : byte_array4_t
    ) return word_array4_t is
        variable result : word_array4_t;
        variable g_word : word_t;
    begin
        g_word := pack_g_word(g_bytes);

        result(0) := curr_words(0) xor g_word;
        result(1) := curr_words(1) xor result(0);
        result(2) := curr_words(2) xor result(1);
        result(3) := curr_words(3) xor result(2);

        return result;
    end function;

    function prev_word3(
        curr_words : word_array4_t
    ) return word_t is
    begin
        return curr_words(3) xor curr_words(2);
    end function;

    function prev_round_words(
        curr_words : word_array4_t;
        g_bytes    : byte_array4_t
    ) return word_array4_t is
        variable result : word_array4_t;
        variable g_word : word_t;
    begin
        g_word := pack_g_word(g_bytes);

        result(3) := curr_words(3) xor curr_words(2);
        result(2) := curr_words(2) xor curr_words(1);
        result(1) := curr_words(1) xor curr_words(0);
        result(0) := curr_words(0) xor g_word;

        return result;
    end function;

begin

    -- These wide outputs are unused in the low-area top level, so keep them
    -- constant to avoid synthesizing extra bookkeeping around the serial stream.
    round_idx_out        <= (others => '0');
    byte_idx_out         <= (others => '0');
    roundkey_block_out   <= (others => '0');
    roundkey_block_valid <= '0';
    last_roundkey_out    <= (others => '0');

    ----------------------------------------------------------------------------
    -- Encrypt-only build
    ----------------------------------------------------------------------------
    enc_only_g : if not support_decrypt generate
        type state_t is (
            IDLE,
            OUT_KEY,
            FWD_G_FILL,
            DONE_ST
        );

        signal state      : state_t := IDLE;
        signal curr_words : word_array4_t := (others => (others => '0'));
        signal g_cache    : byte_array4_t := (others => (others => '0'));

        signal round_no   : unsigned(3 downto 0) := (others => '0');
        signal word_no    : unsigned(1 downto 0) := (others => '0');
        signal lane_no    : unsigned(1 downto 0) := (others => '0');
        signal g_step     : unsigned(1 downto 0) := (others => '0');
        signal start_d    : std_logic := '0';

        signal rk_byte_r  : byte_t := (others => '0');
        signal rk_valid_r : std_logic := '0';

        signal sbox_in    : byte_t := (others => '0');
        signal sbox_out   : byte_t;

        attribute fsm_encoding : string;
        attribute fsm_encoding of state : signal is "sequential";
    begin
        roundkey_byte_out <= rk_byte_r;
        roundkey_valid    <= rk_valid_r;
        busy              <= '1' when (state /= IDLE and state /= DONE_ST) else '0';
        done              <= '1' when state = DONE_ST else '0';

        u_sbox: entity work.aes_sbox_cf
            port map(
                byte_in  => sbox_in,
                usage    => '0',
                byte_out => sbox_out
            );

        sbox_in <= rotword_byte(curr_words(3), to_integer(g_step))
                   when state = FWD_G_FILL else
                   (others => '0');

        process(clk)
            variable start_pulse  : std_logic;
            variable target_round : integer range 0 to 10;
            variable g_bytes_v    : byte_array4_t;
            variable next_words_v : word_array4_t;
        begin
            if rising_edge(clk) then
                rk_valid_r <= '0';

                start_pulse := start and (not start_d);
                start_d     <= start;

                if rst = '1' then
                    state      <= IDLE;
                    curr_words <= (others => (others => '0'));
                    g_cache    <= (others => (others => '0'));
                    round_no   <= (others => '0');
                    word_no    <= (others => '0');
                    lane_no    <= (others => '0');
                    g_step     <= (others => '0');
                    start_d    <= '0';
                    rk_byte_r  <= (others => '0');
                    rk_valid_r <= '0';
                else
                    case state is
                        when IDLE =>
                            if start_pulse = '1' then
                                curr_words <= unpack_key_words(key_in);
                                g_cache    <= (others => (others => '0'));
                                round_no   <= ROUND_0_C;
                                word_no    <= (others => '0');
                                lane_no    <= (others => '0');
                                g_step     <= (others => '0');
                                rk_byte_r  <= (others => '0');
                                state      <= OUT_KEY;
                            end if;

                        when OUT_KEY =>
                            rk_byte_r  <= word_byte(curr_words(to_integer(word_no)), to_integer(lane_no));
                            rk_valid_r <= '1';

                            if lane_no = IDX_LAST_C then
                                lane_no <= (others => '0');

                                if word_no = IDX_LAST_C then
                                    word_no <= (others => '0');

                                    if round_no = ROUND_10_C then
                                        state <= DONE_ST;
                                    else
                                        g_step <= (others => '0');
                                        state  <= FWD_G_FILL;
                                    end if;
                                else
                                    word_no <= word_no + 1;
                                end if;
                            else
                                lane_no <= lane_no + 1;
                            end if;

                        when FWD_G_FILL =>
                            target_round := to_integer(round_no) + 1;

                            case to_integer(g_step) is
                                when 0 =>
                                    g_cache(0) <= sbox_out xor RCON_B(target_round);
                                    g_step     <= g_step + 1;

                                when 1 =>
                                    g_cache(1) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when 2 =>
                                    g_cache(2) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when others =>
                                    g_bytes_v    := g_cache;
                                    g_bytes_v(3) := sbox_out;
                                    next_words_v := next_round_words(curr_words, g_bytes_v);

                                    curr_words <= next_words_v;
                                    round_no   <= round_no + 1;
                                    word_no    <= (others => '0');
                                    lane_no    <= (others => '0');
                                    state      <= OUT_KEY;
                            end case;

                        when DONE_ST =>
                            if start_pulse = '1' then
                                curr_words <= unpack_key_words(key_in);
                                g_cache    <= (others => (others => '0'));
                                round_no   <= ROUND_0_C;
                                word_no    <= (others => '0');
                                lane_no    <= (others => '0');
                                g_step     <= (others => '0');
                                rk_byte_r  <= (others => '0');
                                state      <= OUT_KEY;
                            end if;
                    end case;
                end if;
            end if;
        end process;
    end generate;

    ----------------------------------------------------------------------------
    -- Encrypt / decrypt-capable build
    ----------------------------------------------------------------------------
    enc_dec_g : if support_decrypt generate
        type state_t is (
            IDLE,
            OUT_KEY,
            FWD_G_FILL,
            REV_G_FILL,
            DONE_ST
        );

        signal state      : state_t := IDLE;
        signal curr_words : word_array4_t := (others => (others => '0'));
        signal g_cache    : byte_array4_t := (others => (others => '0'));

        signal round_no   : unsigned(3 downto 0) := (others => '0');
        signal word_no    : unsigned(1 downto 0) := (others => '0');
        signal lane_no    : unsigned(1 downto 0) := (others => '0');
        signal g_step     : unsigned(1 downto 0) := (others => '0');
        signal start_d    : std_logic := '0';
        signal enc_mode_r : std_logic := '1';

        signal rk_byte_r  : byte_t := (others => '0');
        signal rk_valid_r : std_logic := '0';

        signal sbox_in    : byte_t := (others => '0');
        signal sbox_out   : byte_t;

        attribute fsm_encoding : string;
        attribute fsm_encoding of state : signal is "sequential";
    begin
        roundkey_byte_out <= rk_byte_r;
        roundkey_valid    <= rk_valid_r;
        busy              <= '1' when (state /= IDLE and state /= DONE_ST) else '0';
        done              <= '1' when state = DONE_ST else '0';

        u_sbox: entity work.aes_sbox_cf
            port map(
                byte_in  => sbox_in,
                usage    => '0',
                byte_out => sbox_out
            );

        sbox_in <= rotword_byte(curr_words(3), to_integer(g_step))
                   when state = FWD_G_FILL else
                   rotword_byte(prev_word3(curr_words), to_integer(g_step))
                   when state = REV_G_FILL else
                   (others => '0');

        process(clk)
            variable start_pulse  : std_logic;
            variable target_round : integer range 0 to 10;
            variable g_bytes_v    : byte_array4_t;
            variable next_words_v : word_array4_t;
            variable prev_words_v : word_array4_t;
        begin
            if rising_edge(clk) then
                rk_valid_r <= '0';

                start_pulse := start and (not start_d);
                start_d     <= start;

                if rst = '1' then
                    state      <= IDLE;
                    curr_words <= (others => (others => '0'));
                    g_cache    <= (others => (others => '0'));
                    round_no   <= (others => '0');
                    word_no    <= (others => '0');
                    lane_no    <= (others => '0');
                    g_step     <= (others => '0');
                    start_d    <= '0';
                    enc_mode_r <= '1';
                    rk_byte_r  <= (others => '0');
                    rk_valid_r <= '0';
                else
                    case state is
                        when IDLE =>
                            if start_pulse = '1' then
                                curr_words <= unpack_key_words(key_in);
                                g_cache    <= (others => (others => '0'));
                                round_no   <= ROUND_0_C;
                                word_no    <= (others => '0');
                                lane_no    <= (others => '0');
                                g_step     <= (others => '0');
                                enc_mode_r <= encrypt;
                                rk_byte_r  <= (others => '0');

                                if encrypt = '1' then
                                    state <= OUT_KEY;
                                else
                                    state <= FWD_G_FILL;
                                end if;
                            end if;

                        when OUT_KEY =>
                            rk_byte_r  <= word_byte(curr_words(to_integer(word_no)), to_integer(lane_no));
                            rk_valid_r <= '1';

                            if lane_no = IDX_LAST_C then
                                lane_no <= (others => '0');

                                if word_no = IDX_LAST_C then
                                    word_no <= (others => '0');

                                    if enc_mode_r = '1' then
                                        if round_no = ROUND_10_C then
                                            state <= DONE_ST;
                                        else
                                            g_step <= (others => '0');
                                            state  <= FWD_G_FILL;
                                        end if;
                                    else
                                        if round_no = ROUND_0_C then
                                            state <= DONE_ST;
                                        else
                                            g_step <= (others => '0');
                                            state  <= REV_G_FILL;
                                        end if;
                                    end if;
                                else
                                    word_no <= word_no + 1;
                                end if;
                            else
                                lane_no <= lane_no + 1;
                            end if;

                        when FWD_G_FILL =>
                            target_round := to_integer(round_no) + 1;

                            case to_integer(g_step) is
                                when 0 =>
                                    g_cache(0) <= sbox_out xor RCON_B(target_round);
                                    g_step     <= g_step + 1;

                                when 1 =>
                                    g_cache(1) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when 2 =>
                                    g_cache(2) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when others =>
                                    g_bytes_v    := g_cache;
                                    g_bytes_v(3) := sbox_out;
                                    next_words_v := next_round_words(curr_words, g_bytes_v);

                                    curr_words <= next_words_v;
                                    round_no   <= round_no + 1;
                                    word_no    <= (others => '0');
                                    lane_no    <= (others => '0');

                                    if enc_mode_r = '1' then
                                        state <= OUT_KEY;
                                    else
                                        if round_no = ROUND_9_C then
                                            state <= OUT_KEY;
                                        else
                                            g_step <= (others => '0');
                                            state  <= FWD_G_FILL;
                                        end if;
                                    end if;
                            end case;

                        when REV_G_FILL =>
                            target_round := to_integer(round_no);

                            case to_integer(g_step) is
                                when 0 =>
                                    g_cache(0) <= sbox_out xor RCON_B(target_round);
                                    g_step     <= g_step + 1;

                                when 1 =>
                                    g_cache(1) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when 2 =>
                                    g_cache(2) <= sbox_out;
                                    g_step     <= g_step + 1;

                                when others =>
                                    g_bytes_v    := g_cache;
                                    g_bytes_v(3) := sbox_out;
                                    prev_words_v := prev_round_words(curr_words, g_bytes_v);

                                    curr_words <= prev_words_v;
                                    round_no   <= round_no - 1;
                                    word_no    <= (others => '0');
                                    lane_no    <= (others => '0');
                                    state      <= OUT_KEY;
                            end case;

                        when DONE_ST =>
                            if start_pulse = '1' then
                                curr_words <= unpack_key_words(key_in);
                                g_cache    <= (others => (others => '0'));
                                round_no   <= ROUND_0_C;
                                word_no    <= (others => '0');
                                lane_no    <= (others => '0');
                                g_step     <= (others => '0');
                                enc_mode_r <= encrypt;
                                rk_byte_r  <= (others => '0');

                                if encrypt = '1' then
                                    state <= OUT_KEY;
                                else
                                    state <= FWD_G_FILL;
                                end if;
                            end if;
                    end case;
                end if;
            end if;
        end process;
    end generate;

end architecture rtl;
