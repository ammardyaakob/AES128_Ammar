----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03.03.2026 15:15:02
-- Design Name: 
-- Module Name: p2s - Behavioral
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
-- AES Encryption Core: Parallel-to-Serial Converter (2 clock cycle delay)
-- =============================================================================
-- Description:
--   Converts the 32-bit output of the MixColumns multiplier back into a
--   serialised stream of 8-bit bytes, feeding the byte permutation unit one
--   byte per clock cycle.
--
--   As described in Hämäläinen et al. (DSD'06), the MixColumns multiplier
--   produces a complete 32-bit column result (four bytes) every 4 clock cycles.
--   This unit latches that 32-bit word and shifts out the four bytes MSB-first,
--   one byte per cycle, keeping pace with the 8-bit data path of the rest of
--   the AES core.
--
-- Interface:
--   clk        : system clock (rising-edge triggered)
--   rst        : synchronous active-high reset
--   load       : asserted for one cycle when parallel_in holds a valid 32-bit
--                column result from the MixColumns multiplier
--   parallel_in: 32-bit column result (d0 in bits 31..24, d3 in bits 7..0)
--   serial_out : 8-bit serialised output to the byte permutation unit
--   valid      : high while serial_out is producing valid bytes (4 cycles
--                after each load pulse)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity parallel_to_serial is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        load         : in  std_logic;                      -- latch new 32-bit word
        parallel_in  : in  std_logic_vector(31 downto 0); -- from MixColumns
        serial_out   : out std_logic_vector(7  downto 0); -- to byte permutation unit
        valid        : out std_logic;                       -- output byte is valid
        serial_out_dly  : out std_logic_vector(7 downto 0);
        valid_dly       : out std_logic
    );
end entity parallel_to_serial;

architecture rtl of parallel_to_serial is

    -- Internal shift register: holds the 32-bit column result.
    -- Bytes are shifted out from the MSB end so that byte 0 (bits 31..24)
    -- is presented first, matching the column byte order in the AES State.
    signal shift_reg : std_logic_vector(31 downto 0);

    -- 2-bit counter tracks how many bytes remain to be shifted out (0-3).
    -- A separate 'active' flag indicates the converter is mid-transfer.
    signal byte_cnt  : unsigned(1 downto 0);
    signal active    : std_logic;
    
    -- 3-stage delay pipeline for serial_out and valid.
    -- Index 0 = oldest (output), index 2 = newest (just captured from serial_out).
    type pipe_t is array (0 to 3) of std_logic_vector(7 downto 0);
    signal dly_pipe  : pipe_t := (others => (others => '0'));
    
    -- Internal copy of serial_out (combinatorial) so the delay pipe can read it
    signal serial_int : std_logic_vector(7 downto 0);
    signal valid_int  : std_logic;
    
    -- 3-bit shift register for the valid flag delay
    signal valid_sr  : std_logic_vector(2 downto 0) := (others => '0');
begin

    -- -------------------------------------------------------------------------
    -- Sequential process: shift register and control counter
    -- -------------------------------------------------------------------------
    p_shift : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                shift_reg <= (others => '0');
                byte_cnt  <= (others => '0');
                active    <= '0';
                dly_pipe  <= (others => (others => '0'));
                valid_sr  <= (others => '0');

            
            elsif load = '1' then
                -- Latch the new 32-bit column result and start serialisation.
                -- Output the first byte (bits 31..24) immediately next cycle.
                shift_reg <= parallel_in(23 downto 0) & x"00";
                byte_cnt  <= to_unsigned(3, 2) - 1;  -- 3 more bytes after this one

                active    <= '1';

            elsif active = '1' then
                -- Shift left by 8: discard the byte just presented and move
                -- the next byte into the most-significant byte position.
                shift_reg <= shift_reg(23 downto 0) & x"00";

                if byte_cnt = 0 then
                    active <= '0';
                else
                    byte_cnt <= byte_cnt - 1;
                end if;
            end if;
            -- 8-bit data pipe
            dly_pipe(0) <= dly_pipe(1);
            dly_pipe(1) <= dly_pipe(2);
            dly_pipe(2) <= dly_pipe(3);
            dly_pipe(3) <= serial_int;   -- captures current serial_out each cycle
            
            -- 1-bit valid pipe (identical structure)
            valid_sr <= valid_sr(1 downto 0) & valid_int;
        end if;
    end process p_shift;
    

    -- -------------------------------------------------------------------------
    -- Combinatorial outputs
    -- -------------------------------------------------------------------------
    -- The current most-significant byte of the shift register is the output.
    serial_out <= parallel_in(31 downto 24) when active = '0' else shift_reg(31 downto 24);
    valid <= load or active;
    serial_int <= parallel_in(31 downto 24) when active = '0' else shift_reg(31 downto 24);
    valid_int  <= active;
    
    -- Delayed outputs (4 cycles behind serial_out / valid)
    serial_out_dly <= dly_pipe(0);
    valid_dly      <= valid_sr(0);

end architecture rtl;

