library ieee;
use ieee.std_logic_1164.all;

package vcomponents is
    component SRLC32E is
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
    end component;
end package vcomponents;

package body vcomponents is
end package body vcomponents;
