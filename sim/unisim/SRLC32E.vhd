library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity SRLC32E is
    generic (
        INIT : bit_vector := X"00000000"
    );
    port (
        Q   : out std_logic;
        A   : in  std_logic_vector(4 downto 0);
        CE  : in  std_logic;
        CLK : in  std_logic;
        D   : in  std_logic
    );
end entity SRLC32E;

architecture sim of SRLC32E is
    signal shift_reg : std_logic_vector(31 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if CE = '1' then
                shift_reg(31 downto 1) <= shift_reg(30 downto 0);
                shift_reg(0) <= D;
            end if;
        end if;
    end process;

    Q <= shift_reg(to_integer(unsigned(A)));
end architecture sim;
