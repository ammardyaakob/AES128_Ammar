library ieee;
use ieee.std_logic_1164.all;

library std;
use std.env.all;

-- Directed testbench for the parallel-to-serial feedback register.
-- Confirms that each loaded 32-bit word is emitted MSB-first over four valid
-- cycles and that valid de-asserts cleanly after the transfer completes.
entity parallel_to_serial_tb is
end entity parallel_to_serial_tb;

architecture sim of parallel_to_serial_tb is
    constant CLK_PERIOD : time := 10 ns;

    type byte_array4_t is array (0 to 3) of std_logic_vector(7 downto 0);

    constant WORD0_BYTES : byte_array4_t := (x"AA", x"BB", x"CC", x"DD");
    constant WORD1_BYTES : byte_array4_t := (x"11", x"22", x"33", x"44");

    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal load           : std_logic := '0';
    signal parallel_in    : std_logic_vector(31 downto 0) := (others => '0');
    signal serial_out     : std_logic_vector(7 downto 0);
    signal valid          : std_logic;
    signal serial_out_dly : std_logic_vector(7 downto 0);
    signal valid_dly      : std_logic;
begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.parallel_to_serial
        port map (
            clk            => clk,
            rst            => rst,
            load           => load,
            parallel_in    => parallel_in,
            serial_out     => serial_out,
            valid          => valid,
            serial_out_dly => serial_out_dly,
            valid_dly      => valid_dly
        );

    stim : process
        procedure run_case(
            constant word_in  : std_logic_vector(31 downto 0);
            constant expected : byte_array4_t;
            constant case_name : string
        ) is
        begin
            -- Apply a load pulse and check the first byte immediately, matching
            -- the combinational output behaviour of the block.
            parallel_in <= word_in;
            load <= '1';
            wait for 1 ns;
            assert valid = '1'
                report case_name & " valid low at byte 0"
                severity failure;
            assert serial_out = expected(0)
                report case_name & " serial mismatch at byte 0"
                severity failure;

            wait until rising_edge(clk);
            load <= '0';
            parallel_in <= (others => '0');

            -- The remaining three bytes should appear on successive cycles.
            for i in 1 to 3 loop
                wait until falling_edge(clk);
                assert valid = '1'
                    report case_name & " valid low at byte " & integer'image(i)
                    severity failure;
                assert serial_out = expected(i)
                    report case_name & " serial mismatch at byte " & integer'image(i)
                    severity failure;
            end loop;

            wait until falling_edge(clk);
            assert valid = '0'
                report case_name & " valid stayed high after transfer"
                severity failure;
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);

        -- Exercise two independent transfers back to back.
        run_case(x"AABBCCDD", WORD0_BYTES, "parallel_to_serial word0");
        run_case(x"11223344", WORD1_BYTES, "parallel_to_serial word1");

        report "parallel_to_serial_tb PASSED" severity note;
        finish;
    end process;

end architecture sim;
