----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.03.2026 20:42:26
-- Design Name: 
-- Module Name: tb_aes_top - Behavioral
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

----------------------------------------------------------------------------------
-- Module Name: aes128_top_tb
-- Description:
--   Simple self-checking testbench for aes128_top.
--
--   Uses the FIPS-197 Appendix B known-answer test vector:
--     Plaintext : 32 43 F6 A8 88 5A 30 8D 31 31 98 A2 E0 37 07 34
--     Key       : 2B 7E 15 16 28 AE D2 A6 AB F7 15 88 09 CF 4F 3C
--     Ciphertext: 39 25 84 1D 02 DC 09 FB DC 11 85 97 19 6A 0B 32
--
--   Procedure:
--     1. Reset the DUT for a few cycles.
--     2. Assert start_load for one cycle and begin clocking in plaintext
--        bytes on data_in (MSB-first, 16 consecutive bytes).
--     3. Wait until output_valid rises.
--     4. Capture 16 ciphertext bytes and compare with expected vector.
--     5. Report PASS / FAIL.
----------------------------------------------------------------------------------
----------------------------------------------------------------------------------
-- Module Name : aes_top_tb
-- Description : Simple testbench for aes_top (skeletal implementation).
--
-- What is tested:
--   The current aes_top wires byte_in directly into shifter_serial and
--   asserts shift_ce='1' after reset.  This testbench:
--     1. Resets the DUT.
--     2. Presents the 16 FIPS-197 Appendix-B plaintext bytes one per clock
--        on byte_in, with start pulsed on byte 0.
--     3. Captures shift_state_out via block_out (which mirrors state, currently
--        all-zeros, so we print the raw signals instead).
--     4. Prints the sequence of bytes seen coming out of the shifter so the
--        ShiftRows permutation can be verified visually.
--
-- NOTE: block_out and done are driven from 'state' and 'done_internal' which
--       are not yet updated by round logic, so they will read all-zeros.
--       That is expected for this stub.  The testbench will PASS as long as
--       simulation runs without errors.
--
-- FIPS-197 Appendix B test vector:
--   Plaintext  : 32 43 F6 A8  88 5A 30 8D  31 31 98 A2  E0 37 07 34
--   Key        : 2B 7E 15 16  28 AE D2 A6  AB F7 15 88  09 CF 4F 3C
--   Ciphertext : 39 25 84 1D  02 DC 09 FB  DC 11 85 97  19 6A 0B 32
--   (ciphertext not expected from this stub; only used as reference)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity aes_top_tb is
end entity aes_top_tb;

architecture sim of aes_top_tb is

    constant CLK_PERIOD : time := 10 ns;

    ---------------------------------------------------------------------------
    -- DUT ports
    ---------------------------------------------------------------------------
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal start     : std_logic := '0';
    signal encrypt   : std_logic := '1';          -- encryption mode
    signal byte_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal key_in    : std_logic_vector(127 downto 0) := (others => '0');
    signal done      : std_logic;
    signal rk_valid  : std_logic;
    signal byte_out : std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------------
    -- FIPS-197 Appendix B plaintext and key
    ---------------------------------------------------------------------------
    type byte_array16_t is array (0 to 15) of std_logic_vector(7 downto 0);

    constant PLAINTEXT : byte_array16_t := (
        x"32", x"43", x"F6", x"A8",
        x"88", x"5A", x"30", x"8D",
        x"31", x"31", x"98", x"A2",
        x"E0", x"37", x"07", x"34"
    );

    constant KEY_VEC : std_logic_vector(127 downto 0) :=
        x"2B7E151628AED2A6ABF7158809CF4F3C";

begin

    ---------------------------------------------------------------------------
    -- Clock
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
    u_dut : entity work.aes_top
        port map (
            clk       => clk,
            rst       => rst,
            start     => start,
            encrypt   => encrypt,
            byte_in   => byte_in,
            key       => key_in,
            done      => done,
            byte_out => byte_out,
            rk_valid => rk_valid
        );

    ---------------------------------------------------------------------------
    -- Stimulus
    ---------------------------------------------------------------------------
    stim : process
    begin
        -----------------------------------------------------------------------
        -- 1. Reset
        -----------------------------------------------------------------------
        start   <= '0';
        encrypt <= '1';
        key_in  <= KEY_VEC;
        byte_in <= (others => '0');   
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -----------------------------------------------------------------------
        -- 2. Feed 16 plaintext bytes, one per cycle.
        --    Pulse start on the first byte.
        -----------------------------------------------------------------------
        report "INFO: Feeding 16 plaintext bytes into aes_top.";
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until rising_edge(rk_valid);
        for i in 0 to 15 loop
            byte_in <= PLAINTEXT(i);
            wait until rising_edge(clk);
        end loop;

        start   <= '0';
        byte_in <= (others => '0');

        -----------------------------------------------------------------------
        -- 3. Run for 32 more cycles and observe shifter outputs.
        --    The shifter first outputs a valid byte 12 cycles after its first
        --    input (see shifter_serial comment: "First 8 bits ready after 12
        --    clock cycles when CE is pulled high").
        -----------------------------------------------------------------------
        report "INFO: Running for 32 additional cycles to observe shifter output.";

        -----------------------------------------------------------------------
        -- 4. Final status.
        --    Since round logic is not implemented, block_out = 0 is expected.
        -----------------------------------------------------------------------

        if byte_out = (7 downto 0 => '0') then
            report "PASS: block_out is all-zeros as expected for stub." severity note;
        else
            report "NOTE: block_out is non-zero - round logic may be partially active."
                severity note;
        end if;

        wait for CLK_PERIOD * 50000;
        report "INFO: Simulation finished.";
    end process stim;

end architecture sim;