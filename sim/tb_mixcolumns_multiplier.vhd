library ieee;
use ieee.std_logic_1164.all;

library std;
use std.env.all;

-- Directed testbench for the iterative MixColumns engine.
-- It feeds one column byte per cycle and checks both forward and inverse modes
-- against a standard AES example column.
entity tb_mixcolumns_multiplier is
end entity tb_mixcolumns_multiplier;

architecture sim of tb_mixcolumns_multiplier is
    constant CLK_PERIOD : time := 10 ns;

    type byte_array4_t is array (0 to 3) of std_logic_vector(7 downto 0);

    constant MIX_IN  : byte_array4_t := (x"D4", x"BF", x"5D", x"30");
    constant MIX_OUT : byte_array4_t := (x"04", x"66", x"81", x"E5");

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal en      : std_logic := '0';
    signal inverse : std_logic := '0';
    signal d_in    : std_logic_vector(7 downto 0) := (others => '0');
    signal d0_out  : std_logic_vector(7 downto 0);
    signal d1_out  : std_logic_vector(7 downto 0);
    signal d2_out  : std_logic_vector(7 downto 0);
    signal d3_out  : std_logic_vector(7 downto 0);
begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.mixcolumns_multiplier
        generic map (
            support_inverse => true
        )
        port map (
            clk     => clk,
            rst     => rst,
            en      => en,
            inverse => inverse,
            d_in    => d_in,
            d0_out  => d0_out,
            d1_out  => d1_out,
            d2_out  => d2_out,
            d3_out  => d3_out
        );

    stim : process
        procedure run_case(
            constant inv_mode : std_logic;
            constant column_in : byte_array4_t;
            constant expected  : byte_array4_t;
            constant case_name : string
        ) is
        begin
            -- Reset between cases so each column starts from a known accumulator state.
            rst <= '1';
            en <= '0';
            d_in <= (others => '0');
            inverse <= inv_mode;
            wait until rising_edge(clk);
            rst <= '0';

            en <= '1';
            d_in <= column_in(0);
            wait until rising_edge(clk);

            -- Bytes 1..3 are accumulated while en is low and active remains internal.
            en <= '0';
            d_in <= column_in(1);
            wait until rising_edge(clk);

            d_in <= column_in(2);
            wait until rising_edge(clk);

            d_in <= column_in(3);
            wait until rising_edge(clk);
            wait for 1 ns;

            assert d0_out = expected(0) report case_name & " d0 mismatch" severity failure;
            assert d1_out = expected(1) report case_name & " d1 mismatch" severity failure;
            assert d2_out = expected(2) report case_name & " d2 mismatch" severity failure;
            assert d3_out = expected(3) report case_name & " d3 mismatch" severity failure;
        end procedure;
    begin
        -- Forward and inverse cases should be exact inverses of each other.
        run_case('0', MIX_IN, MIX_OUT, "MixColumns");
        run_case('1', MIX_OUT, MIX_IN, "InvMixColumns");

        report "tb_mixcolumns_multiplier PASSED" severity note;
        finish;
    end process;

end architecture sim;
