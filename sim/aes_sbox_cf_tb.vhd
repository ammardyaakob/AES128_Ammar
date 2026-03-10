----------------------------------------------------------------------------------
-- Company: The University of Sheffield
-- Engineer: Cian Thomson
-- 
-- Create Date: 20.02.2026 10:12:36
-- Module Name: aes_sbox_cf_tb
-- Project Name: aes
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

----------------------------------------------------------------------------------

entity aes_sbox_cf_tb is
end aes_sbox_cf_tb;

----------------------------------------------------------------------------------

architecture RTL of aes_sbox_cf_tb is

    ------------------------------------------------------------------------------
    -- Component declaration
    ------------------------------------------------------------------------------
    component aes_sbox_cf
        port (
            byte_in  : in  std_logic_vector(7 downto 0);
            usage  : in  std_logic;
            byte_out : out std_logic_vector(7 downto 0)
        );
    end component;

    ------------------------------------------------------------------------------
    -- Testbench signals
    ------------------------------------------------------------------------------
    signal byte_in_tb  : std_logic_vector(7 downto 0);
    signal inverse_tb  : std_logic;
    signal byte_out_tb : std_logic_vector(7 downto 0);

begin

    ------------------------------------------------------------------------------
    -- Unit Under Test
    ------------------------------------------------------------------------------
    uut : aes_sbox_cf
        port map (
            byte_in  => byte_in_tb,
            usage  => inverse_tb,
            byte_out => byte_out_tb
        );

    ------------------------------------------------------------------------------
    -- Stimulus process
    ------------------------------------------------------------------------------
    stim_proc : process
    begin
    
        --------------------------------------------------------------------------
        -- TEST 1: Forward s-box tests (inverse = '0')
        --------------------------------------------------------------------------
        inverse_tb <= '0';

        byte_in_tb <= x"00";  -- expect 63
        wait for 10 ns;

        byte_in_tb <= x"01";  -- expect 7C
        wait for 10 ns;

        byte_in_tb <= x"53";  -- expect ED
        wait for 10 ns;

        byte_in_tb <= x"7C";  -- expect 10
        wait for 10 ns;

        byte_in_tb <= x"AE";  -- expect E4
        wait for 10 ns;

        byte_in_tb <= x"FF";  -- expect 16
        wait for 10 ns;

        --------------------------------------------------------------------------
        -- TEST 2: Inverse s-box tests (usage = '1')
        --------------------------------------------------------------------------
        inverse_tb <= '1';

        byte_in_tb <= x"63";  -- expect 00
        wait for 10 ns;

        byte_in_tb <= x"7C";  -- expect 01
        wait for 10 ns;

        byte_in_tb <= x"ED";  -- expect 53
        wait for 10 ns;

        byte_in_tb <= x"10";  -- expect 7C
        wait for 10 ns;

        byte_in_tb <= x"E4";  -- expect AE
        wait for 10 ns;

        byte_in_tb <= x"16";  -- expect FF
        wait for 10 ns;
        
        wait;
        
    end process;

end RTL;