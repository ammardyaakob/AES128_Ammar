library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--////////////////////////////////////////////////////////////////////////////////
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.02.2026 12:03:26
-- Design Name: 
-- Module Name: shifter32x8byteintb
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: VHDL testbench for shifter32x8byteinvhd
-- 
-- Dependencies: shifter32x8byteinvhd
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
--////////////////////////////////////////////////////////////////////////////////

entity shifter32x8byteintbvhd is
end shifter32x8byteintbvhd;

architecture behavioral of shifter32x8byteintbvhd is
    
    ----------------------------------------------------------------
    -- Component Declaration
    ----------------------------------------------------------------
    component shifter_serial
        port (
            clk       : in  std_logic;
            state_in  : in  std_logic_vector(7 downto 0);
            state_out : out std_logic_vector(7 downto 0);
            ce        : in  std_logic
        );
    end component;
    
    ----------------------------------------------------------------
    -- DUT signals
    ----------------------------------------------------------------
    signal clk              : std_logic := '0';
    signal state_in         : std_logic_vector(127 downto 0);
    signal state_out        : std_logic_vector(127 downto 0);
    signal byte_in          : std_logic_vector(7 downto 0);
    signal byte_out         : std_logic_vector(7 downto 0);
    signal counter          : unsigned(3 downto 0) := (others => '0');
    signal assign_counter   : unsigned(3 downto 0) := (others => '0');
    signal start            : std_logic := '0';
    signal ce               : std_logic;
    signal start_assign     : std_logic := '0';
    
    -- Clock period definition
    constant clk_period : time := 10 ns;
    
begin
    
    ----------------------------------------------------------------
    -- Instantiate DUT
    ----------------------------------------------------------------
    dut : shifter_serial
        port map (
            clk       => clk,
            state_in  => byte_in,
            state_out => byte_out,
            ce        => ce
        );
    
    ----------------------------------------------------------------
    -- Clock generation - 10 ns period (100 MHz)
    ----------------------------------------------------------------
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;
    
    ----------------------------------------------------------------
    -- Main process
    ----------------------------------------------------------------
    main_process : process(clk)
    begin
        if rising_edge(clk) then
            if start = '1' then
                -- Extract byte from state_in based on counter
                byte_in <= state_in(to_integer(counter)*8 + 7 downto to_integer(counter)*8);
                ce <= '1';
                counter <= counter + 1;
                
                if counter = 13 then
                    start_assign <= '1';
                end if;
                
                if start_assign = '1' then
                    -- Assign byte_out to state_out based on assign_counter
                    state_out(to_integer(assign_counter)*8 + 7 downto to_integer(assign_counter)*8) <= byte_out;
                    assign_counter <= assign_counter + 1;
                end if;
            end if;
        end if;
    end process;
    
    ----------------------------------------------------------------
    -- Stimulus process
    ----------------------------------------------------------------
    stimulus : process
    begin
        -- AES test vector
        state_in <= x"00112233_44556677_8899aabb_ccddeeff";
        wait for 100 ns;
        start <= '1';
    end process;
    
end behavioral;