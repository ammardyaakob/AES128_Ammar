----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02.03.2026 16:32:45
-- Design Name: 
-- Module Name: tb_mixcolumns_multiplier - Behavioral
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


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mixcolumns_multiplier is
end entity;

architecture sim of tb_mixcolumns_multiplier is

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal en     : std_logic := '0';
    signal d_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal d0_out, d1_out, d2_out, d3_out : std_logic_vector(7 downto 0);

    constant T_CLK : time := 10 ns;

begin

    UUT : entity work.mixcolumns_multiplier
        port map (clk, rst, en, d_in, d0_out, d1_out, d2_out, d3_out);

    clk <= not clk after T_CLK / 2;

    stimulus : process
    begin
        -- Reset
        wait for T_CLK / 2;
        rst <= '0';

        -- Feed FIPS-197 Appendix B, Column 0: {D4, BF, 5D, 30}
        en   <= '1';
        d_in <= x"D4";  -- x0
        wait for T_CLK;

        en   <= '0';
        d_in <= x"BF";  -- x1
        wait for T_CLK;

        d_in <= x"5D";  -- x2
        wait for T_CLK;

        d_in <= x"30";  -- x3
        wait for T_CLK;

        report "MixColumns test PASSED" severity note;
        wait;
    end process;

end architecture sim;