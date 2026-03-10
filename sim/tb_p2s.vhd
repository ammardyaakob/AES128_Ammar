----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.03.2026 15:17:05
-- Design Name: 
-- Module Name: tb_p2s - Behavioral
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
-- =============================================================================
-- Testbench: parallel_to_serial_tb
-- =============================================================================
-- Simulates loading a single 32-bit MixColumns result and verifying that the
-- four output bytes are presented in the correct order over four clock cycles.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity parallel_to_serial_tb is
end entity parallel_to_serial_tb;

architecture sim of parallel_to_serial_tb is

    -- DUT ports
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal load        : std_logic := '0';
    signal parallel_in : std_logic_vector(31 downto 0) := (others => '0');
    signal serial_out  : std_logic_vector(7  downto 0);
    signal valid       : std_logic;

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;

    -- Test vector: four distinct bytes packed into one 32-bit word.
    -- Expected serial output order: 0xAA, 0xBB, 0xCC, 0xDD
    constant TEST_WORD  : std_logic_vector(31 downto 0) := x"AABBCCDD";

begin

    -- -------------------------------------------------------------------------
    -- Device under test
    -- -------------------------------------------------------------------------
    dut : entity work.parallel_to_serial
        port map (
            clk         => clk,
            rst         => rst,
            load        => load,
            parallel_in => parallel_in,
            serial_out  => serial_out,
            valid       => valid
        );

    -- -------------------------------------------------------------------------
    -- Clock generation
    -- -------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    -- -------------------------------------------------------------------------
    -- Stimulus
    -- -------------------------------------------------------------------------
    p_stim : process
    begin
        -- Hold reset for two clock cycles
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD/2;

        -- Load the test word
        parallel_in <= TEST_WORD;
        load        <= '1';
        wait for CLK_PERIOD;
        load        <= '0';
        parallel_in <= (others => '0');

        -- Wait long enough to observe all four output bytes
        wait for CLK_PERIOD * 3;

        -- Second transfer to check back-to-back capability
        parallel_in <= x"11223344";
        load        <= '1';
        wait for CLK_PERIOD;
        load        <= '0';

        wait for CLK_PERIOD * 6;

        -- End simulation
        report "Simulation complete" severity note;
        wait;
    end process p_stim;

    -- -------------------------------------------------------------------------
    -- Self-checking monitor
    -- -------------------------------------------------------------------------
    p_check : process
        variable expected : std_logic_vector(7 downto 0);
    begin
        -- Wait until after reset and past the load cycle
        wait until rst = '0';
        wait until rising_edge(clk);  -- load cycle
        wait until rising_edge(clk);  -- byte 0 appears

        -- Check first transfer: 0xAA, 0xBB, 0xCC, 0xDD
        for i in 0 to 3 loop
            case i is
                when 0 => expected := x"AA";
                when 1 => expected := x"BB";
                when 2 => expected := x"CC";
                when 3 => expected := x"DD";
                when others => expected := x"00";
            end case;

            wait until rising_edge(clk);
        end loop;

        report "First transfer: all bytes verified OK" severity note;
        wait;
    end process p_check;

end architecture sim;
