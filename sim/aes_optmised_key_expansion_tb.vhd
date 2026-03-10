----------------------------------------------------------------------------------
-- Company: University of Sheffield
-- Engineer: David Cracknell
-- 
-- Create Date: 02/03/2026 02:34:50 PM
-- Design Name: 
-- Module Name: aes_optmised_key_expansion_tb - Behavioral
-- Project Name: group 1 aes loew area
-- Description: tb for aes_key_expansion_vhd
-- 
-- Dependencies: aes_optmised_key_expansion.vhd
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library std;
use std.textio.all;
use IEEE.STD_LOGIC_TEXTIO.ALL;  -- hwrite

entity aes_key_expansion_tb is
end entity aes_key_expansion_tb;

architecture tb of aes_key_expansion_tb is

    component aes_key_expansion
        port(
            clk    : in  std_logic;
            rst    : in  std_logic;
            start  : in  std_logic;
            key_in : in  std_logic_vector(127 downto 0);

            roundkey_byte_out   : out std_logic_vector(7 downto 0);
            roundkey_valid      : out std_logic;
            round_idx_out       : out std_logic_vector(3 downto 0);
            byte_idx_out        : out std_logic_vector(3 downto 0);

            roundkey_block_out   : out std_logic_vector(127 downto 0);
            roundkey_block_valid : out std_logic;

            last_roundkey_out : out std_logic_vector(127 downto 0);

            busy : out std_logic;
            done : out std_logic
        );
    end component;

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '0';
    signal start  : std_logic := '0';
    signal key_in : std_logic_vector(127 downto 0) := (others => '0');

    signal roundkey_byte_out   : std_logic_vector(7 downto 0);
    signal roundkey_valid      : std_logic;
    signal round_idx_out       : std_logic_vector(3 downto 0);
    signal byte_idx_out        : std_logic_vector(3 downto 0);

    signal roundkey_block_out   : std_logic_vector(127 downto 0);
    signal roundkey_block_valid : std_logic;

    signal last_roundkey_out : std_logic_vector(127 downto 0);

    signal busy : std_logic;
    signal done : std_logic;

    -- Waveform-visible result flags
    signal tb_pass : std_logic := '0';
    signal tb_fail : std_logic := '0';

    constant CLK_PERIOD : time := 10 ns;

    type rk_array_t is array (0 to 10) of std_logic_vector(127 downto 0);
    constant EXPECTED_RKS : rk_array_t := (
        x"000102030405060708090A0B0C0D0E0F", -- Round 0
        x"D6AA74FDD2AF72FADAA678F1D6AB76FE", -- Round 1
        x"B692CF0B643DBDF1BE9BC5006830B3FE", -- Round 2
        x"B6FF744ED2C2C9BF6C590CBF0469BF41", -- Round 3
        x"47F7F7BC95353E03F96C32BCFD058DFD", -- Round 4
        x"3CAAA3E8A99F9DEB50F3AF57ADF622AA", -- Round 5
        x"5E390F7DF7A69296A7553DC10AA31F6B", -- Round 6
        x"14F9701AE35FE28C440ADF4D4EA9C026", -- Round 7
        x"47438735A41C65B9E016BAF4AEBF7AD2", -- Round 8
        x"549932D1F08557681093ED9CBE2C974E", -- Round 9
        x"13111D7FE3944A17F307A78B4D2B30C5"  -- Round 10
    );

begin

    uut: aes_key_expansion
        port map (
            clk => clk,
            rst => rst,
            start => start,
            key_in => key_in,

            roundkey_byte_out => roundkey_byte_out,
            roundkey_valid    => roundkey_valid,
            round_idx_out     => round_idx_out,
            byte_idx_out      => byte_idx_out,

            roundkey_block_out   => roundkey_block_out,
            roundkey_block_valid => roundkey_block_valid,

            last_roundkey_out => last_roundkey_out,

            busy => busy,
            done => done
        );

    clk <= not clk after CLK_PERIOD/2;

    stim_proc : process
        variable captured_msb : std_logic_vector(127 downto 0) := (others => '0');
        variable captured_lsb : std_logic_vector(127 downto 0) := (others => '0');

        variable r_idx : integer := 0; -- 0..10
        variable b_idx : integer := 0; -- 0..15

        variable stream_count   : integer := 0;
        variable rounds_checked : integer := 0;
        variable fail_count     : integer := 0;
        variable timeout_cycles : integer := 0;

        variable saw_lsb_order  : boolean := false;

        procedure print_hex128(prefix : in string; v : in std_logic_vector(127 downto 0)) is
            variable LL : line;
        begin
            write(LL, prefix);
            hwrite(LL, v);
            writeline(output, LL);
        end procedure;

        procedure print_msg(msg : in string) is
            variable LL : line;
        begin
            write(LL, msg);
            writeline(output, LL);
        end procedure;

    begin
        tb_pass <= '0';
        tb_fail <= '0';

        key_in <= x"000102030405060708090A0B0C0D0E0F";
        rst    <= '1';
        start  <= '0';

        wait for 5*CLK_PERIOD;
        rst <= '0';
        wait for 2*CLK_PERIOD;

        print_msg("Starting test (stream-only, byte-order tolerant)...");
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        while done /= '1' loop
            wait until rising_edge(clk);
            timeout_cycles := timeout_cycles + 1;

            if roundkey_valid = '1' then
                -- MSB-first packing: byte 0 -> bits 127..120
                captured_msb(127 - b_idx*8 downto 120 - b_idx*8) := roundkey_byte_out;

                -- LSB-first packing: byte 0 -> bits 7..0
                captured_lsb(b_idx*8 + 7 downto b_idx*8) := roundkey_byte_out;

                stream_count := stream_count + 1;

                if b_idx = 15 then
                    if (r_idx < 0) or (r_idx > 10) then
                        print_msg("FAIL: TB round index out of range (r_idx=" & integer'image(r_idx) & ")");
                        fail_count := fail_count + 1;
                    else
                        if captured_msb = EXPECTED_RKS(r_idx) then
                            print_msg("PASS: Round " & integer'image(r_idx) & " matches (MSB-first stream)");
                        elsif captured_lsb = EXPECTED_RKS(r_idx) then
                            print_msg("PASS: Round " & integer'image(r_idx) & " matches (LSB-first stream)");
                            saw_lsb_order := true;
                        else
                            print_msg("FAIL: Round key mismatch at round " & integer'image(r_idx));
                            print_hex128("  Expected: ", EXPECTED_RKS(r_idx));
                            print_hex128("  Got MSB : ", captured_msb);
                            print_hex128("  Got LSB : ", captured_lsb);
                            fail_count := fail_count + 1;
                        end if;
                    end if;

                    rounds_checked := rounds_checked + 1;
                    r_idx := r_idx + 1;
                    b_idx := 0;
                    captured_msb := (others => '0');
                    captured_lsb := (others => '0');
                else
                    b_idx := b_idx + 1;
                end if;
            end if;

            if timeout_cycles > 6000 then
                print_msg("FAIL: Timeout waiting for done='1'");
                fail_count := fail_count + 1;
                exit;
            end if;
        end loop;

        wait until rising_edge(clk);

        if busy /= '0' then
            print_msg("FAIL: busy not low after completion");
            fail_count := fail_count + 1;
        end if;

        if stream_count /= 176 then
            print_msg("FAIL: Incorrect streamed byte count. Got " & integer'image(stream_count) & ", expected 176");
            fail_count := fail_count + 1;
        else
            print_msg("PASS: Correct total streamed byte count (176)");
        end if;

        if rounds_checked /= 11 then
            print_msg("FAIL: Incorrect number of round keys checked. Got " & integer'image(rounds_checked) & ", expected 11");
            fail_count := fail_count + 1;
        else
            print_msg("PASS: Correct number of round keys checked (11)");
        end if;

        if r_idx /= 11 then
            print_msg("FAIL: TB round counter ended at " & integer'image(r_idx) & " (expected 11)");
            fail_count := fail_count + 1;
        end if;

        if saw_lsb_order then
            print_msg("NOTE: Your DUT streams bytes LSB-first vs FIPS-197 hex presentation.");
        end if;

        if fail_count = 0 then
            tb_pass <= '1';
            tb_fail <= '0';
            print_msg("==================================================");
            print_msg("TEST PASSED: aes_key_expansion (stream-only)");
            print_msg("==================================================");
        else
            tb_pass <= '0';
            tb_fail <= '1';
            print_msg("==================================================");
            print_msg("TEST FAILED: aes_key_expansion (stream-only)");
            print_msg("Number of failures = " & integer'image(fail_count));
            print_msg("==================================================");
        end if;

        wait;
    end process;

end architecture tb;
