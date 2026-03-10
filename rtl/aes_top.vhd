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

entity aes_top is
    port(
        clk      : in  std_logic;
        rst      : in  std_logic;
        start    : in  std_logic;
        encrypt  : in  std_logic; -- '1'=encrypt, '0'=decrypt
        byte_in  : in  std_logic_vector(7 downto 0);
        key   : in  std_logic_vector(127 downto 0);
        done     : out std_logic;
        byte_out : out std_logic_vector(7 downto 0);
        rk_valid : out std_logic
    );
end entity;

architecture rtl of aes_top is

    -- Round keys: 11 * 128 bits = 1408 bits
    signal shift_state_in    : std_logic_vector(7 downto 0);
    signal shift_state_out    : std_logic_vector(7 downto 0);
    signal shift_ce    : std_logic := '0';
    signal shift_done    : std_logic;
    
    signal mc_d0_out : std_logic_vector(7 downto 0);
    signal mc_d1_out : std_logic_vector(7 downto 0);
    signal mc_d2_out : std_logic_vector(7 downto 0);
    signal mc_d3_out : std_logic_vector(7 downto 0);
    signal mc_rst : std_logic := '0';
    signal mc_en : std_logic := '0';
    
    signal roundkey_byte_out        : std_logic_vector(7 downto 0);
    signal roundkey_valid           : std_logic;
    signal roundkey_rst             : std_logic := '0';
    signal roundkey_start           : std_logic := '0';
    signal roundkey_done            : std_logic := '0';

    signal sub_byte_in : std_logic_vector(7 downto 0);
    signal sub_byte_out : std_logic_vector(7 downto 0);
    signal sub_usage : std_logic := '0';
    
    signal p2s_parallel_in : std_logic_vector(31 downto 0);
    signal p2s_load : std_logic := '0';
    signal p2s_valid : std_logic;
    signal p2s_serial_out : std_logic_vector(7 downto 0);
    signal p2s_serial_out_dly : std_logic_vector(7 downto 0);
    signal p2s_valid_dly : std_logic;
    
    signal sbox_flag         : std_logic;
    signal roundkey_counter     : integer range 0 to 10 := 0;
    signal running           : std_logic := '0';
    signal done_internal : std_logic := '0';
    signal running_mc : std_logic := '0';
    signal mc_counter : integer range 0 to 3 := 0;
    signal column_counter : integer range 0 to 15 := 0;
    signal byte_out_reg : std_logic_vector(7 downto 0);
    signal done_reg : std_logic := '0';
    
    -- ShiftRows Output delay to line up the last round with missing mixcolumns time slot
    type pipe_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal shift_dly_pipe  : pipe_t := (others => (others => '0'));
    signal shift_out_counter : integer range 0 to 4 := 0;


        -- Unused
    signal round_idx_out            : std_logic_vector(3 downto 0);
    signal byte_idx_out             : std_logic_vector(3 downto 0);
    signal roundkey_block_out       : std_logic_vector(127 downto 0);
    signal roundkey_block_valid     : std_logic;
    signal last_roundkey_out        : std_logic_vector(127 downto 0);
    signal roundkey_busy            : std_logic;
    
    
    
    type fsm_t is (start_roundkey, start_shift,start_mc,new_column, start_p2s, start_pre_main_loop, pre_main_loop, start_main_loop, main_loop);
    signal fsm : fsm_t;
    
    type input_t is (bytes, p2s, p2s_delayed);
    signal input_type : input_t;

begin
    
    ------------------------------------------------------------------------
    -- AES submodules
    ------------------------------------------------------------------------

    -- ShiftRows 
    shift_inst: entity work.shifter_serial
        port map(state_in => sub_byte_out, state_out => shift_state_out, clk=> clk, ce=>shift_ce, done => shift_done);

    -- MixColumns
    mix_inst: entity work.mixcolumns_multiplier
        port map(d_in => shift_state_out, 
        d0_out => mc_d0_out,
        d1_out => mc_d1_out,
        d2_out => mc_d2_out,
        d3_out => mc_d3_out,
        clk => clk,
        rst => mc_rst,
        en => mc_en);
    
    -- SubBytes
    sub_inst: entity work.aes_sbox_cf
        port map(
        byte_in => sub_byte_in,
        byte_out => sub_byte_out,
        usage => sub_usage
        );
        
    -- RoundKeys
    roundkey_inst: entity work.aes_key_expansion
    port map(
        clk                  => clk,
        rst                  => rst,
        start                => roundkey_start,
        key_in               => key,
        roundkey_byte_out    => roundkey_byte_out,
        roundkey_valid       => roundkey_valid,
        round_idx_out        => round_idx_out,
        byte_idx_out         => byte_idx_out,
        roundkey_block_out   => roundkey_block_out,
        roundkey_block_valid => roundkey_block_valid,
        last_roundkey_out    => last_roundkey_out,
        busy                 => roundkey_busy,
        done                 => roundkey_done
    );
    
    p2s_inst: entity work.parallel_to_serial
    port map(
        clk => clk,
        rst => rst,
        load => p2s_load,
        parallel_in => p2s_parallel_in,
        serial_out => p2s_serial_out,
        valid => p2s_valid,
        serial_out_dly => p2s_serial_out_dly,
        valid_dly => p2s_valid_dly
    );
    

    ------------------------------------------------------------------------
    -- AES control process
    ------------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst='1' then
            running <= '0';
            done_internal <= '0';
            fsm <= start_roundkey;
        elsif rising_edge(clk) then
            if (roundkey_counter = 11) then
                if (shift_out_counter = 4)then
                    byte_out_reg <= shift_dly_pipe(4) xor roundkey_byte_out;
                else
                    byte_out_reg <= shift_dly_pipe(0) xor roundkey_byte_out;
                    shift_out_counter <= shift_out_counter + 1;
                end if;
                -- Set done = 1 for when byte_out is streaming
                if (roundkey_valid = '1') then
                    done_reg <= '1';
                else
                    done_reg <= '0';
                end if;
            end if;
            -- Shift Output Delay
            shift_dly_pipe(0) <= shift_dly_pipe(1);
            shift_dly_pipe(1) <= shift_dly_pipe(2);
            shift_dly_pipe(2) <= shift_dly_pipe(3);
            shift_dly_pipe(3) <= shift_dly_pipe(4);
            shift_dly_pipe(4) <= shift_dly_pipe(5);
            shift_dly_pipe(5) <= shift_dly_pipe(6);
            shift_dly_pipe(6) <= shift_dly_pipe(7);
            shift_dly_pipe(7) <= shift_state_out;
            if (start = '1')then    
                running <= '1';
                roundkey_start <= '1';
            elsif (running = '1')then
                -- State Machine
                case fsm is
                    when start_roundkey =>
                        roundkey_start <= '0';
                        input_type <= bytes;
                        mc_rst <='1';
                        if (roundkey_valid = '1')then
                            fsm <= start_shift;
                        end if;
                    when start_shift =>
                        if (shift_done = '1') then
                            mc_en <= '1';
                            mc_rst <= '0';
                            fsm <= start_mc;
                            mc_counter <= 0;
                        end if;
                    when start_mc =>
                        mc_en <= '0';
                        if (mc_counter = 2) then
                            fsm <= new_column;
                        else
                            mc_counter <= mc_counter + 1;
                        end if;
                     when new_column =>
                        mc_en <= '0';
                        column_counter <= column_counter + 1;
                        p2s_load <= '1';
                        fsm <= start_p2s;
                        mc_counter <= 0;
                        input_type <= p2s_delayed;

                     when start_p2s =>
                        p2s_load <= '0';
                        mc_en <= '0';
                        mc_rst <='1';
                        if (p2s_valid = '1')then
                            fsm <= start_pre_main_loop;
                        end if;
                     when start_pre_main_loop =>
                        column_counter <= column_counter + 1;
                        mc_counter <= 0;
                        fsm <= pre_main_loop;
                     when pre_main_loop =>
                        if (mc_counter = 2) then
                            fsm <= start_main_loop;
                            column_counter <= 0;
                            mc_en <='0';
                        elsif (mc_counter = 1) then
                            mc_rst <='0';
                            mc_en <= '1';
                            mc_counter <= mc_counter + 1;
                        else
                            mc_counter <= mc_counter + 1;
                        end if;
                     when start_main_loop =>
                        mc_counter <= 0;
                        fsm <= main_loop;
                        column_counter <= column_counter + 1;
                     when main_loop =>
                        if (column_counter = 4) then
                            column_counter <= 0;
                            fsm <= new_column;
                        elsif (mc_counter = 2) then
                            fsm <= start_main_loop;
                            mc_en <='0';
                            p2s_load <='0';
                        elsif (mc_counter = 1) then
                            mc_rst <='0';
                            mc_en <= '1';
                            mc_counter <= mc_counter + 1;
                            p2s_load <='1';
                            input_type <= p2s;
                        else
                            mc_counter <= mc_counter + 1;
                        end if;
                end case;
                    
            end if;
        end if;
    end process;
    
    process(roundkey_valid, rst)
    begin
        if rst='1' then 
            roundkey_counter <= 0;
        elsif rising_edge(roundkey_valid) then
            roundkey_counter <= roundkey_counter + 1;
        end if;
    end process;
    -- Data output
    
    byte_out <= byte_out_reg;
    rk_valid <= roundkey_valid;
    done <= done_reg;
    
    -- Keep shift enabled for final round, so delayed output will line up with last key.
    shift_ce <= roundkey_valid;
    p2s_parallel_in <= mc_d0_out & mc_d1_out & mc_d2_out & mc_d3_out;
    sub_byte_in <= byte_in xor roundkey_byte_out when input_type = bytes else 
                   p2s_serial_out xor roundkey_byte_out when input_type = p2s else
                   p2s_serial_out_dly xor roundkey_byte_out when input_type = p2s_delayed;

    -- SBox flag: '0' = encryption, '1' = decryption
    sbox_flag <= not encrypt;

end architecture;
