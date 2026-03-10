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
--   Parallel-to-serial converter for the AES feedback path.
--   The block accepts one 32-bit MixColumns result, emits the four bytes
--   MSB-first over four cycles, and also provides a delayed copy of the byte
--   stream to help the top-level controller align the first feedback column.
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

entity parallel_to_serial is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        load           : in  std_logic;                      -- Latch a new 32-bit word
        parallel_in    : in  std_logic_vector(31 downto 0); -- MixColumns result
        serial_out     : out std_logic_vector(7 downto 0);  -- Byte-serial output
        valid          : out std_logic;                     -- High when serial_out is valid
        serial_out_dly : out std_logic_vector(7 downto 0);  -- Delayed byte stream
        valid_dly      : out std_logic                      -- Delayed valid qualifier
    );
end entity parallel_to_serial;

architecture rtl of parallel_to_serial is

    -- Holds the current 32-bit column result. Bytes are shifted out from the
    -- MSB end so byte 0 appears first, matching AES column ordering.
    signal shift_reg : std_logic_vector(31 downto 0);

    -- Tracks the number of remaining bytes and whether a transfer is active.
    signal byte_cnt  : unsigned(1 downto 0);
    signal active    : std_logic;

    -- Delay pipe used by the top-level AES controller to compensate for the
    -- initial feedback latency around MixColumns and ShiftRows.
    type pipe_t is array (0 to 3) of std_logic_vector(7 downto 0);
    signal dly_pipe : pipe_t := (others => (others => '0'));

    signal serial_curr : std_logic_vector(7 downto 0);
    signal valid_curr  : std_logic;

    -- Companion delay for valid so the qualifier stays aligned with the data.
    signal valid_sr : std_logic_vector(2 downto 0) := (others => '0');

begin

    --------------------------------------------------------------------------
    -- Shift register and transfer control
    --------------------------------------------------------------------------
    p_shift : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                shift_reg <= (others => '0');
                byte_cnt  <= (others => '0');
                active    <= '0';
                dly_pipe  <= (others => (others => '0'));
                valid_sr  <= (others => '0');

            elsif load = '1' then
                -- Latch a new column and prepare to emit the remaining three
                -- bytes over subsequent cycles.
                shift_reg <= parallel_in(23 downto 0) & x"00";
                byte_cnt  <= to_unsigned(2, byte_cnt'length);
                active    <= '1';

            elsif active = '1' then
                -- Shift left by one byte so the next byte moves into the MSB
                -- position used by serial_curr.
                shift_reg <= shift_reg(23 downto 0) & x"00";

                if byte_cnt = 0 then
                    active <= '0';
                else
                    byte_cnt <= byte_cnt - 1;
                end if;
            end if;

            if (load = '1') or (active = '1') or (valid_sr /= "000") then
                -- Continue advancing the delay pipeline while valid samples are
                -- entering or older samples are still draining out.
                dly_pipe(0) <= dly_pipe(1);
                dly_pipe(1) <= dly_pipe(2);
                dly_pipe(2) <= dly_pipe(3);

                if valid_curr = '1' then
                    dly_pipe(3) <= serial_curr;
                else
                    dly_pipe(3) <= (others => '0');
                end if;

                valid_sr <= valid_sr(1 downto 0) & valid_curr;
            end if;
        end if;
    end process p_shift;

    --------------------------------------------------------------------------
    -- Combinational outputs
    --------------------------------------------------------------------------
    -- The current MSB byte is always the byte presented to the consumer. On
    -- the load cycle the first byte comes directly from parallel_in.
    serial_curr <= parallel_in(31 downto 24) when active = '0' else shift_reg(31 downto 24);
    valid_curr  <= load or active;

    serial_out     <= serial_curr;
    valid          <= valid_curr;
    serial_out_dly <= dly_pipe(0);
    valid_dly      <= valid_sr(0);

end architecture rtl;
