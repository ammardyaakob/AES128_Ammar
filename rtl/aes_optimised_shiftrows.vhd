----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 25.02.2026 13:10:36
-- Design Name: 
-- Module Name: shifter_serial - Behavioral
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
Library UNISIM;
use UNISIM.vcomponents.all;

-- 8 bit SHIFTROWS function using SRLC32E Primitives and address tapping
-- First 8 bits ready after 12 clock cycles when CE is pulled high.
-- Pipelinable after 16 clock cycles.

entity shifter_serial is
port ( 
    state_in    : in Std_Logic_Vector(7 downto 0);
    state_out   : out Std_Logic_Vector(7 downto 0);
    ce          : in std_logic;
    clk         : in std_logic;
    done        : out std_logic
    );
end shifter_serial;

architecture Behavioral of shifter_serial is
    signal A                : std_logic_vector(4 downto 0) := "00011";
    signal state            : INTEGER RANGE 0 TO 15;
    signal srl_out          : std_logic_vector(7 downto 0);
    signal state_out_reg    : std_logic_vector(7 downto 0);
    signal done_reg         : std_logic := '0';
    signal srl_out_reg      : std_logic_vector(7 downto 0);
begin
    process(clk,ce,srl_out)
        begin
           if rising_edge(clk) then
              if ce = '1' then
                 case state is
                    when 0 =>
                       state        <= 1;
                       A(4 downto 2) <= "001";
                    when 1 =>                
                       state        <= 2;
                       A(4 downto 2) <= "000";
                    when 2 =>
                       A(4 downto 2) <= "011";
                       state        <= 3;
                    when 3 =>
                       state        <= 4;
                       A(4 downto 2) <= "010";
                    when 4 =>
                       state        <= 5;
                       A(4 downto 2) <= "001";
                    when 5 =>
                       state        <= 6;
                       A(4 downto 2) <= "100";
                    when 6 =>
                       state        <= 7;
                       A(4 downto 2) <= "011";
                    when 7 =>
                       state        <= 8;
                       A(4 downto 2) <= "010";
                    when 8 =>
                       state        <= 9;
                       A(4 downto 2) <= "101";
                    when 9 =>
                       state        <= 10;
                       A(4 downto 2) <= "100";
                    when 10 =>
                       state        <= 11;
                       A(4 downto 2) <= "011";
                       done_reg <= '1';
                    when 11 =>
                       state        <= 12;
                       A(4 downto 2) <= "010";
                    when 12 =>
                       state        <= 13;
                       A(4 downto 2) <= "001";
                    when 13 =>
                       state        <= 14;
                       A(4 downto 2) <= "000";
                    when 14 =>
                       state <= 15;
                    when 15 =>
                       state        <= 0;
                       A(4 downto 2) <= "010";
                 end case;
              end if;
           end if;
        end process;
    
    
    state_out <= state_in when state = 15 else srl_out;
    done <= done_reg;
    
    -- 8 SRL32CE Primitives
    gen_srl : for i in 0 to 7 generate
    begin
    
       SRLC32E_inst : SRLC32E
       generic map (
          INIT => X"00000000"
       )
       port map (
          Q   => srl_out(i),     -- SRL data output
          A   => A,              -- 5-bit shift depth select input
          CE  => ce,             -- Clock enable input
          CLK => clk,            -- Clock input
          D   => state_in(i)     -- SRL data input
       );
    
    end generate gen_srl;

end Behavioral;


