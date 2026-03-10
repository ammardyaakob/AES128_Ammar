----------------------------------------------------------------------------------
-- Company: University of Sheffield
-- Engineer: Amaan Mujawar
-- 
-- Create Date: 02/11/2026 03:01:41 PM
-- Design Name: 
-- Module Name: aes_top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:
--   Top-level AES-128 controller for a low-area byte-serial datapath.
--   Encryption reuses a single S-box, a serial ShiftRows stage, an iterative
--   MixColumns block and a byte-stream key schedule, so only one state byte is
--   processed per cycle through most of the round logic.
--   Decryption reuses the same S-box but stores all round keys in on-chip RAM
--   and walks them backwards, avoiding a dedicated reverse-order key expander
--   in the instantiated key schedule.
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.aes_mixcolumns_pkg.all;
use work.aes_shiftrows_pkg.all;

entity aes_top is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        start    : in  std_logic;                       -- Start pulse for a 16-byte block transaction
        encrypt  : in  std_logic;                       -- '1' = encrypt, '0' = decrypt
        byte_in  : in  std_logic_vector(7 downto 0);   -- Byte-serial plaintext/ciphertext input
        key      : in  std_logic_vector(127 downto 0); -- AES-128 cipher key
        done     : out std_logic;                      -- Output-valid indicator for the final result stream
        byte_out : out std_logic_vector(7 downto 0);   -- Byte-serial ciphertext/plaintext output
        rk_valid : out std_logic                       -- Exposes the round-key byte cadence for debug/inspection
    );
end entity;

architecture rtl of aes_top is
    subtype byte_t is std_logic_vector(7 downto 0);
    -- 16-byte state storage used by the buffered decrypt path.
    type byte_array16_t is array (0 to 15) of byte_t;
    -- 11 round keys x 16 bytes. Used as a compact RAM-backed decrypt key store.
    type roundkey_store_t is array (0 to 175) of byte_t;

    ------------------------------------------------------------------------
    -- Shared encrypt datapath signals
    ------------------------------------------------------------------------
    -- Serial ShiftRows output. This stage reorders bytes over time instead of
    -- building a full 128-bit crossbar, trading latency for lower area.
    signal shift_state_out : std_logic_vector(7 downto 0);
    -- ShiftRows advances once per valid round-key byte during encryption.
    signal shift_ce        : std_logic := '0';
    signal shift_done      : std_logic;
    
    -- Iterative MixColumns accumulator outputs for one 32-bit AES column.
    signal mc_d0_out : std_logic_vector(7 downto 0);
    signal mc_d1_out : std_logic_vector(7 downto 0);
    signal mc_d2_out : std_logic_vector(7 downto 0);
    signal mc_d3_out : std_logic_vector(7 downto 0);
    signal mc_data_in : byte_t := (others => '0');
    signal mc_rst : std_logic := '0';
    signal mc_en : std_logic := '0';
    
    signal roundkey_byte_out        : std_logic_vector(7 downto 0);
    signal roundkey_valid           : std_logic;
    signal roundkey_start           : std_logic := '0';

    -- Shared S-box interface. The same combinational S-box serves encryption,
    -- decrypt inverse SubBytes, and key expansion.
    signal sub_byte_in : std_logic_vector(7 downto 0);
    signal sub_byte_out : std_logic_vector(7 downto 0);
    signal sub_usage : std_logic := '0';
    
    -- MixColumns emits a full 32-bit column; p2s re-serialises it so the next
    -- round can continue on the same 8-bit datapath.
    signal p2s_parallel_in : std_logic_vector(31 downto 0);
    signal p2s_load : std_logic := '0';
    signal p2s_valid : std_logic;
    signal p2s_serial_out : std_logic_vector(7 downto 0);
    signal p2s_serial_out_dly : std_logic_vector(7 downto 0);
    -- Common inverse-mode flag for the S-box, ShiftRows and MixColumns.
    signal sbox_flag         : std_logic;
    -- Counts round-key valid bursts so the final encryption round can be aligned
    -- with the delayed ShiftRows output.
    signal roundkey_counter : integer range 0 to 11 := 0;
    signal roundkey_valid_d : std_logic := '0';
    signal running          : std_logic := '0';
    -- Byte position within one MixColumns column and column position within a round.
    signal mc_counter : integer range 0 to 3 := 0;
    signal column_counter : integer range 0 to 4 := 0;
    signal byte_out_reg : std_logic_vector(7 downto 0);
    signal done_reg : std_logic := '0';
    -- The first input byte is latched explicitly because the first round-key byte
    -- arrives on the same cycle that the transaction starts.
    signal first_input_byte : std_logic_vector(7 downto 0) := (others => '0');
    -- Holds later input bytes until the round-key stream indicates they are consumed.
    signal byte_in_aligned : std_logic_vector(7 downto 0) := (others => '0');
    
    -- The final AES round omits MixColumns. This delay line keeps the last
    -- ShiftRows output aligned with the streamed final round key.
    type pipe_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal shift_dly_pipe : pipe_t := (others => (others => '0'));
    -- Encrypt FSM controls the byte-serial round pipeline.
    type fsm_t is (
        start_roundkey,
        start_shift,
        start_mc,
        new_column,
        start_p2s,
        start_pre_main_loop,
        pre_main_loop,
        start_main_loop,
        main_loop
    );
    signal fsm : fsm_t;
    
    -- Selects which byte source feeds the AddRoundKey/SubBytes path.
    type input_t is (bytes, p2s, p2s_delayed);
    signal input_type : input_t;

    ------------------------------------------------------------------------
    -- Buffered decrypt datapath signals
    ------------------------------------------------------------------------
    -- Decrypt runs from a stored 16-byte state image because the round keys are
    -- applied in reverse order and the round structure differs from encryption.
    type dec_fsm_t is (
        dec_idle,
        dec_capture,
        dec_init_prime,
        dec_init_xor,
        dec_subbytes,
        dec_addkey_prime,
        dec_addkey_xor,
        dec_mixcol,
        dec_final_prime,
        dec_final_xor,
        dec_output
    );
    signal dec_fsm : dec_fsm_t := dec_idle;
    signal dec_state_bytes : byte_array16_t := (others => (others => '0'));
    signal dec_work_bytes  : byte_array16_t := (others => (others => '0'));
    -- Forward-generated round keys are buffered here and then read backwards for decrypt.
    signal dec_roundkeys   : roundkey_store_t;
    signal dec_key_store_idx   : integer range 0 to 176 := 0;
    signal dec_input_store_idx : integer range 0 to 16 := 0;
    signal dec_key_block_idx   : integer range 1 to 10 := 1;
    signal dec_byte_idx        : integer range 0 to 15 := 0;
    signal dec_col_idx         : integer range 0 to 3 := 0;
    signal dec_output_idx      : integer range 0 to 15 := 0;
    signal dec_rk_wr_en        : std_logic := '0';
    signal dec_rk_wr_addr      : integer range 0 to 175 := 0;
    signal dec_rk_wr_data      : byte_t := (others => '0');
    signal dec_rk_rd_addr      : integer range 0 to 175 := 0;
    signal dec_rk_rd_data      : byte_t := (others => '0');
    signal dec_rk_base_addr    : integer range 0 to 160 := 0;

    attribute ram_style : string;
    -- Encourage implementation in block RAM so reverse key storage does not
    -- consume large numbers of LUTRAM resources.
    attribute ram_style of dec_roundkeys : signal is "block";

begin
    
    ------------------------------------------------------------------------
    -- AES submodules
    ------------------------------------------------------------------------

    -- ShiftRows
    shift_inst: entity work.shifter_serial
        generic map (
            support_inverse => true
        )
        port map (
            state_in  => sub_byte_out,
            state_out => shift_state_out,
            clk       => clk,
            ce        => shift_ce,
            rst       => rst,
            inverse   => sbox_flag,
            done      => shift_done
        );

    -- MixColumns
    mix_inst: entity work.mixcolumns_multiplier
        generic map (
            support_inverse => true
        )
        port map (
            d_in    => mc_data_in,
            d0_out  => mc_d0_out,
            d1_out  => mc_d1_out,
            d2_out  => mc_d2_out,
            d3_out  => mc_d3_out,
            clk     => clk,
            rst     => mc_rst,
            en      => mc_en,
            inverse => sbox_flag
        );
    
    -- SubBytes
    sub_inst: entity work.aes_sbox_cf
        port map (
            byte_in  => sub_byte_in,
            byte_out => sub_byte_out,
            usage    => sub_usage
        );
        
    -- RoundKeys
    roundkey_inst: entity work.aes_key_expansion
        generic map (
            support_decrypt => false
        )
        port map (
            clk                  => clk,
            rst                  => rst,
            start                => roundkey_start,
            -- Always stream keys in forward order; decrypt reuses the BRAM copy
            -- and walks it backwards instead of synthesizing reverse key logic.
            encrypt              => '1',
            key_in               => key,
            roundkey_byte_out    => roundkey_byte_out,
            roundkey_valid       => roundkey_valid,
            round_idx_out        => open,
            byte_idx_out         => open,
            roundkey_block_out   => open,
            roundkey_block_valid => open,
            last_roundkey_out    => open,
            busy                 => open,
            done                 => open
        );
    
    p2s_inst: entity work.parallel_to_serial
        port map (
            clk            => clk,
            rst            => rst,
            load           => p2s_load,
            parallel_in    => p2s_parallel_in,
            serial_out     => p2s_serial_out,
            valid          => p2s_valid,
            serial_out_dly => p2s_serial_out_dly,
            valid_dly      => open
        );

    ------------------------------------------------------------------------
    -- Round-key RAM access for decrypt mode
    -- Writes occur during dec_capture; reads are synchronous so the decrypt FSM
    -- uses explicit "prime" states before each XOR phase.
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if dec_rk_wr_en = '1' then
                dec_roundkeys(dec_rk_wr_addr) <= dec_rk_wr_data;
            end if;
            dec_rk_rd_data <= dec_roundkeys(dec_rk_rd_addr);
        end if;
    end process;
    

    ------------------------------------------------------------------------
    -- AES control process
    ------------------------------------------------------------------------
    process (clk, rst)
        variable dec_col_v : std_logic_vector(31 downto 0);
        variable dec_mix_v : std_logic_vector(31 downto 0);
    begin
        if rst = '1' then
            -- Asynchronous reset clears all control/state registers. The BRAM
            -- contents are not explicitly erased; they are treated as invalid
            -- until the next decrypt key-capture sequence repopulates them.
            running <= '0';
            roundkey_start <= '0';
            mc_rst <= '1';
            mc_en <= '0';
            p2s_load <= '0';
            input_type <= bytes;
            mc_counter <= 0;
            column_counter <= 0;
            byte_out_reg <= (others => '0');
            done_reg <= '0';
            first_input_byte <= (others => '0');
            byte_in_aligned <= (others => '0');
            shift_dly_pipe <= (others => (others => '0'));
            fsm <= start_roundkey;
            dec_fsm <= dec_idle;
            dec_state_bytes <= (others => (others => '0'));
            dec_work_bytes <= (others => (others => '0'));
            dec_key_store_idx <= 0;
            dec_input_store_idx <= 0;
            dec_key_block_idx <= 1;
            dec_byte_idx <= 0;
            dec_col_idx <= 0;
            dec_output_idx <= 0;
            dec_rk_wr_en <= '0';
            dec_rk_wr_addr <= 0;
            dec_rk_wr_data <= (others => '0');
            dec_rk_rd_addr <= 0;
            dec_rk_base_addr <= 0;
        elsif rising_edge(clk) then
            -- Default write disable. Individual decrypt states raise this for
            -- one cycle when storing a round-key byte.
            dec_rk_wr_en <= '0';

            -- Capture the current input byte only when the round-key stream is
            -- ready for it. This keeps the byte-serial plaintext/ciphertext input
            -- aligned with the streamed AddRoundKey operation.
            if (roundkey_valid = '1') and (input_type = bytes) then
                byte_in_aligned <= byte_in;
            end if;

            if encrypt = '1' then
                -- Encryption presents the final byte only when the delayed
                -- ShiftRows result and the final round key are simultaneously valid.
                if (roundkey_valid = '1') and
                   (((roundkey_counter = 10) and (roundkey_valid_d = '0')) or
                    (roundkey_counter = 11)) then
                    byte_out_reg <= shift_dly_pipe(4) xor roundkey_byte_out;
                    done_reg <= '1';
                else
                    done_reg <= '0';
                end if;

                if shift_ce = '1' then
                    shift_dly_pipe(0) <= shift_dly_pipe(1);
                    shift_dly_pipe(1) <= shift_dly_pipe(2);
                    shift_dly_pipe(2) <= shift_dly_pipe(3);
                    shift_dly_pipe(3) <= shift_dly_pipe(4);
                    shift_dly_pipe(4) <= shift_dly_pipe(5);
                    shift_dly_pipe(5) <= shift_dly_pipe(6);
                    shift_dly_pipe(6) <= shift_dly_pipe(7);
                    shift_dly_pipe(7) <= shift_state_out;
                end if;

                if start = '1' then
                    -- Launch a new encrypt transaction. The key schedule starts
                    -- immediately and the first data byte is latched separately.
                    first_input_byte <= byte_in;
                    running <= '1';
                    roundkey_start <= '1';
                elsif (running = '1')then
                    -- The round-key byte stream is the master timing reference for
                    -- the encrypt datapath. The FSM mainly inserts the latency
                    -- needed by serial ShiftRows, iterative MixColumns and p2s.
                    case fsm is
                        -- Start the key scheduler and wait for the first round-key byte.
                        when start_roundkey =>
                            roundkey_start <= '0';
                            input_type <= bytes;
                            mc_rst <= '1';
                            if roundkey_valid = '1' then
                                fsm <= start_shift;
                            end if;
                        -- Allow ShiftRows to build enough history before the first
                        -- MixColumns column accumulation begins.
                        when start_shift =>
                            if (shift_done = '1') then
                                mc_en <= '1';
                                mc_rst <= '0';
                                fsm <= start_mc;
                                mc_counter <= 0;
                            end if;
                        -- Accumulate the remaining bytes of the current column in
                        -- the iterative MixColumns block.
                        when start_mc =>
                            mc_en <= '0';
                            if (mc_counter = 2) then
                                fsm <= new_column;
                            else
                                mc_counter <= mc_counter + 1;
                            end if;
                         -- A full 32-bit column is now ready. Load it into the
                         -- serializer so the next round can consume it one byte
                         -- at a time without widening the datapath.
                        when new_column =>
                            mc_en <= '0';
                            column_counter <= column_counter + 1;
                            p2s_load <= '1';
                            fsm <= start_p2s;
                            mc_counter <= 0;
                            input_type <= p2s_delayed;

                         -- Wait for the serializer to present the first recycled
                         -- column byte. The delayed path is used here to match the
                         -- initial pipeline fill timing.
                        when start_p2s =>
                            p2s_load <= '0';
                            mc_en <= '0';
                            mc_rst <= '1';
                            if p2s_valid = '1' then
                                fsm <= start_pre_main_loop;
                            end if;
                         -- One-time transition from the first completed column into
                         -- the repeating steady-state encrypt loop.
                        when start_pre_main_loop =>
                            column_counter <= column_counter + 1;
                            mc_counter <= 0;
                            fsm <= pre_main_loop;
                         -- Finish priming the MixColumns/p2s feedback latency so
                         -- every later column can be processed in a fixed cadence.
                        when pre_main_loop =>
                            if (mc_counter = 2) then
                                fsm <= start_main_loop;
                                column_counter <= 0;
                                mc_en <= '0';
                            elsif (mc_counter = 1) then
                                mc_rst <= '0';
                                mc_en <= '1';
                                mc_counter <= mc_counter + 1;
                            else
                                mc_counter <= mc_counter + 1;
                            end if;
                        -- Open a new steady-state column iteration.
                        when start_main_loop =>
                            mc_counter <= 0;
                            fsm <= main_loop;
                            column_counter <= column_counter + 1;
                        -- Steady-state loop:
                        --   1. consume bytes from the p2s feedback path,
                        --   2. launch MixColumns on the incoming shifted byte,
                        --   3. serialize the completed previous column.
                        -- Four such column iterations complete one AES round.
                        when main_loop =>
                            if (column_counter = 4) then
                                column_counter <= 0;
                                fsm <= new_column;
                            elsif (mc_counter = 2) then
                                fsm <= start_main_loop;
                                mc_en <= '0';
                                p2s_load <= '0';
                            elsif (mc_counter = 1) then
                                mc_rst <= '0';
                                mc_en <= '1';
                                mc_counter <= mc_counter + 1;
                                p2s_load <= '1';
                                input_type <= p2s;
                            else
                                mc_counter <= mc_counter + 1;
                            end if;
                    end case;
                end if;
            else
                -- Decrypt uses a separate buffered control path. The shared
                -- serial MixColumns/p2s pipeline is idle in this mode.
                done_reg <= '0';
                p2s_load <= '0';
                input_type <= bytes;
                roundkey_start <= '0';
                mc_rst <= '1';
                mc_en <= '0';

                case dec_fsm is
                    -- Wait for a new block. On start, reset all decrypt indices
                    -- and launch the forward round-key generator.
                    when dec_idle =>
                        running <= '0';
                        if start = '1' then
                            first_input_byte <= byte_in;
                            running <= '1';
                            roundkey_start <= '1';
                            dec_fsm <= dec_capture;
                            dec_state_bytes <= (others => (others => '0'));
                            dec_work_bytes <= (others => (others => '0'));
                            dec_key_store_idx <= 0;
                            dec_input_store_idx <= 0;
                            dec_key_block_idx <= 1;
                            dec_byte_idx <= 0;
                            dec_col_idx <= 0;
                            dec_output_idx <= 0;
                            dec_rk_wr_addr <= 0;
                            dec_rk_rd_addr <= 0;
                            dec_rk_base_addr <= 0;
                        end if;

                    -- Capture two streams in parallel:
                    --   1. store all 176 forward round-key bytes into BRAM,
                    --   2. latch the 16-byte ciphertext block into local state.
                    -- This avoids building reverse key logic into the shared
                    -- key scheduler and keeps decrypt sequencing simple.
                    when dec_capture =>
                        if roundkey_valid = '1' then
                            if dec_key_store_idx < 176 then
                                dec_rk_wr_en <= '1';
                                dec_rk_wr_addr <= dec_key_store_idx;
                                dec_rk_wr_data <= roundkey_byte_out;
                                dec_key_store_idx <= dec_key_store_idx + 1;
                            end if;

                            if (roundkey_valid_d = '0') and (dec_input_store_idx = 0) then
                                dec_state_bytes(0) <= first_input_byte;
                                dec_input_store_idx <= 1;
                            elsif (roundkey_valid_d = '1') and (dec_input_store_idx < 16) then
                                dec_state_bytes(dec_input_store_idx) <= byte_in;
                                dec_input_store_idx <= dec_input_store_idx + 1;
                            end if;
                        elsif dec_key_store_idx = 176 then
                            dec_byte_idx <= 0;
                            dec_rk_base_addr <= 160;
                            dec_rk_rd_addr <= 160;
                            dec_fsm <= dec_init_prime;
                        end if;

                    -- Prime the synchronous BRAM read for the initial AddRoundKey
                    -- using the last round key (round 10).
                    when dec_init_prime =>
                        dec_rk_rd_addr <= dec_rk_base_addr + 1;
                        dec_fsm <= dec_init_xor;

                    -- Apply the initial AddRoundKey byte by byte.
                    when dec_init_xor =>
                        dec_state_bytes(dec_byte_idx) <= dec_state_bytes(dec_byte_idx) xor dec_rk_rd_data;

                        if dec_byte_idx = 15 then
                            dec_key_block_idx <= 1;
                            dec_byte_idx <= 0;
                            dec_fsm <= dec_subbytes;
                        else
                            if dec_byte_idx < 14 then
                                dec_rk_rd_addr <= dec_rk_base_addr + dec_byte_idx + 2;
                            end if;
                            dec_byte_idx <= dec_byte_idx + 1;
                        end if;

                    -- Perform InvShiftRows and InvSubBytes together. The input
                    -- byte address is permuted by shiftrows_src_idx, so no
                    -- separate inverse ShiftRows storage network is required.
                    when dec_subbytes =>
                        dec_work_bytes(dec_byte_idx) <= sub_byte_out;
                        if dec_byte_idx = 15 then
                            dec_byte_idx <= 0;
                            if dec_key_block_idx = 10 then
                                dec_rk_base_addr <= 0;
                                dec_rk_rd_addr <= 0;
                                dec_fsm <= dec_final_prime;
                            else
                                dec_rk_base_addr <= 160 - (dec_key_block_idx * 16);
                                dec_rk_rd_addr <= 160 - (dec_key_block_idx * 16);
                                dec_fsm <= dec_addkey_prime;
                            end if;
                        else
                            dec_byte_idx <= dec_byte_idx + 1;
                        end if;

                    -- Prime the BRAM read for the next reverse-order round key.
                    when dec_addkey_prime =>
                        dec_rk_rd_addr <= dec_rk_base_addr + 1;
                        dec_fsm <= dec_addkey_xor;

                    -- AddRoundKey for rounds 9 down to 1.
                    when dec_addkey_xor =>
                        dec_work_bytes(dec_byte_idx) <= dec_work_bytes(dec_byte_idx) xor dec_rk_rd_data;

                        if dec_byte_idx = 15 then
                            dec_col_idx <= 0;
                            dec_fsm <= dec_mixcol;
                        else
                            if dec_byte_idx < 14 then
                                dec_rk_rd_addr <= dec_rk_base_addr + dec_byte_idx + 2;
                            end if;
                            dec_byte_idx <= dec_byte_idx + 1;
                        end if;

                    -- InvMixColumns is applied one 32-bit column at a time using
                    -- the package function. This is less serial than the encrypt
                    -- path, but it keeps the decrypt controller compact once the
                    -- full state is already buffered locally.
                    when dec_mixcol =>
                        dec_col_v := dec_work_bytes(dec_col_idx * 4) &
                                     dec_work_bytes(dec_col_idx * 4 + 1) &
                                     dec_work_bytes(dec_col_idx * 4 + 2) &
                                     dec_work_bytes(dec_col_idx * 4 + 3);
                        dec_mix_v := mixcolumns_transform(dec_col_v, '1');
                        dec_state_bytes(dec_col_idx * 4)     <= dec_mix_v(31 downto 24);
                        dec_state_bytes(dec_col_idx * 4 + 1) <= dec_mix_v(23 downto 16);
                        dec_state_bytes(dec_col_idx * 4 + 2) <= dec_mix_v(15 downto 8);
                        dec_state_bytes(dec_col_idx * 4 + 3) <= dec_mix_v(7 downto 0);

                        if dec_col_idx = 3 then
                            dec_key_block_idx <= dec_key_block_idx + 1;
                            dec_byte_idx <= 0;
                            dec_fsm <= dec_subbytes;
                        else
                            dec_col_idx <= dec_col_idx + 1;
                            dec_fsm <= dec_mixcol;
                        end if;

                    -- Prime the BRAM read for the final AddRoundKey. The final
                    -- AES decrypt round omits InvMixColumns.
                    when dec_final_prime =>
                        dec_rk_rd_addr <= dec_rk_base_addr + 1;
                        dec_fsm <= dec_final_xor;

                    -- Final AddRoundKey after the last InvSubBytes/InvShiftRows pass.
                    when dec_final_xor =>
                        dec_state_bytes(dec_byte_idx) <= dec_work_bytes(dec_byte_idx) xor dec_rk_rd_data;

                        if dec_byte_idx = 15 then
                            dec_output_idx <= 0;
                            dec_fsm <= dec_output;
                        else
                            if dec_byte_idx < 14 then
                                dec_rk_rd_addr <= dec_rk_base_addr + dec_byte_idx + 2;
                            end if;
                            dec_byte_idx <= dec_byte_idx + 1;
                        end if;

                    -- Stream the recovered plaintext bytes back out. The state is
                    -- already fully computed, so this stage is output formatting only.
                    when dec_output =>
                        done_reg <= '1';
                        byte_out_reg <= dec_state_bytes(dec_output_idx);

                        if dec_output_idx = 15 then
                            running <= '0';
                            dec_output_idx <= 0;
                            dec_fsm <= dec_idle;
                        else
                            dec_output_idx <= dec_output_idx + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    -- Counts round-key valid rising edges. This small helper counter avoids a
    -- wider explicit encrypt round tracker and is only used for final-round timing.
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                roundkey_counter <= 0;
                roundkey_valid_d <= '0';
            else
                if (roundkey_valid = '1') and (roundkey_valid_d = '0') and (roundkey_counter < 11) then
                    roundkey_counter <= roundkey_counter + 1;
                end if;

                roundkey_valid_d <= roundkey_valid;
            end if;
        end if;
    end process;
    -- Registered top-level outputs.
    
    byte_out <= byte_out_reg;
    rk_valid <= roundkey_valid;
    done <= done_reg;
    
    -- ShiftRows advances on each valid encrypt byte, including the final round.
    -- Keeping it active in the final round ensures the delayed alignment pipe
    -- still tracks the correct byte when MixColumns is omitted.
    shift_ce <= roundkey_valid when encrypt = '1' else '0';
    mc_data_in <= shift_state_out;
    p2s_parallel_in <= mc_d0_out & mc_d1_out & mc_d2_out & mc_d3_out;
    -- Shared AddRoundKey/S-box input mux:
    --   bytes       : initial state input bytes,
    --   p2s         : steady-state MixColumns feedback,
    --   p2s_delayed : initial feedback alignment after the first column,
    --   decrypt     : inverse ShiftRows byte selection from stored state.
    sub_byte_in <= dec_state_bytes(shiftrows_src_idx(dec_byte_idx, '1'))
                   when (encrypt = '0') and (dec_fsm = dec_subbytes) else
                   first_input_byte xor roundkey_byte_out
                   when (roundkey_valid = '1') and (roundkey_valid_d = '0') and (input_type = bytes) else
                   byte_in xor roundkey_byte_out
                   when (roundkey_valid = '1') and (input_type = bytes) else
                   p2s_serial_out xor roundkey_byte_out
                   when (roundkey_valid = '1') and (input_type = p2s) else
                   p2s_serial_out_dly xor roundkey_byte_out
                   when (roundkey_valid = '1') and (input_type = p2s_delayed) else
                   (others => '0');
    -- The same composite-field S-box is reused for forward and inverse lookup.
    -- In decrypt mode the inverse lookup is only active during dec_subbytes.
    sub_usage <= '1' when (encrypt = '0') and (dec_fsm = dec_subbytes) else
                 sbox_flag when roundkey_valid = '1' else '0';

    -- Shared inverse-mode flag for S-box, ShiftRows and MixColumns.
    sbox_flag <= not encrypt;

end architecture;
