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
--   Serial ShiftRows / InvShiftRows stage implemented with SRLC32E primitives.
--   Bytes are accepted one at a time and the required AES row rotation is
--   realised by selecting different SRL tap addresses instead of permuting a
--   full 128-bit state register.
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
library UNISIM;
use UNISIM.vcomponents.all;

package aes_shiftrows_pkg is
    -- Return the source-state byte index that appears at output index idx
    -- after ShiftRows or InvShiftRows.
    function shiftrows_src_idx(
        idx          : integer range 0 to 15;
        inverse_mode : std_logic
    ) return integer;
end package aes_shiftrows_pkg;

package body aes_shiftrows_pkg is

    -- Helper for modulo-4 arithmetic with negative intermediate values.
    function wrap_mod4(value : integer) return integer is
    begin
        return ((value mod 4) + 4) mod 4;
    end function;

    function shiftrows_src_idx(
        idx          : integer range 0 to 15;
        inverse_mode : std_logic
    ) return integer is
        -- AES state is treated in column-major order:
        --   row = idx mod 4, column = idx / 4.
        variable row_v     : integer range 0 to 3;
        variable col_v     : integer range 0 to 3;
        variable src_col_v : integer range 0 to 3;
    begin
        row_v := idx mod 4;
        col_v := idx / 4;

        if inverse_mode = '1' then
            src_col_v := wrap_mod4(col_v - row_v);
        else
            src_col_v := (col_v + row_v) mod 4;
        end if;

        return src_col_v * 4 + row_v;
    end function;

end package body aes_shiftrows_pkg;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity shifter_serial is
    generic (
        support_inverse : boolean := true
    );
    port (
        state_in  : in  std_logic_vector(7 downto 0); -- Incoming byte stream
        state_out : out std_logic_vector(7 downto 0); -- Permuted byte stream
        ce        : in  std_logic;                    -- Advance one byte when high
        clk       : in  std_logic;
        rst       : in  std_logic := '0';
        inverse   : in  std_logic := '0';            -- '1' selects InvShiftRows
        done      : out std_logic                    -- Priming complete for a new block
    );
end shifter_serial;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library UNISIM;
use UNISIM.vcomponents.all;
use work.aes_shiftrows_pkg.all;

architecture Behavioral of shifter_serial is

    -- Byte counter within the 16-byte AES state.
    signal state    : integer range 0 to 15 := 0;
    -- Common SRL output for the currently selected tap.
    signal srl_out  : std_logic_vector(7 downto 0);
    signal done_reg : std_logic := '0';
    -- Tap address selects how far back in the serial history to read.
    signal tap_addr : std_logic_vector(4 downto 0) := "00011";

    -- Initial tap value after reset. This aligns the first useful outputs once
    -- enough bytes have been shifted into the SRLs.
    function initial_addr(
        inverse_mode : std_logic
    ) return std_logic_vector is
    begin
        if support_inverse and (inverse_mode = '1') then
            return std_logic_vector(to_unsigned(11, 5));
        end if;

        return std_logic_vector(to_unsigned(3, 5));
    end function;

    -- Tap schedule for each byte position. The hard-coded addresses map the
    -- streamed byte sequence to the AES ShiftRows / InvShiftRows permutation
    -- while keeping the implementation to one set of SRL primitives.
    function next_addr_for_state(
        idx          : integer range 0 to 15;
        inverse_mode : std_logic
    ) return std_logic_vector is
        variable addr_v : integer range 0 to 31 := 3;
    begin
        if support_inverse and (inverse_mode = '1') then
            case idx is
                when 0      => addr_v := 15;
                when 1      => addr_v := 3;
                when 2      => addr_v := 7;
                when 3      => addr_v := 11;
                when 4      => addr_v := 15;
                when 5      => addr_v := 19;
                when 6      => addr_v := 7;
                when 7      => addr_v := 11;
                when 8      => addr_v := 15;
                when 9      => addr_v := 19;
                when 10     => addr_v := 23;
                when 11     => addr_v := 11;
                when 12     => addr_v := 11;
                when 13     => addr_v := 3;
                when 14     => addr_v := 7;
                when others => addr_v := 11;
            end case;
        else
            case idx is
                when 0      => addr_v := 7;
                when 1      => addr_v := 3;
                when 2      => addr_v := 15;
                when 3      => addr_v := 11;
                when 4      => addr_v := 7;
                when 5      => addr_v := 19;
                when 6      => addr_v := 15;
                when 7      => addr_v := 11;
                when 8      => addr_v := 23;
                when 9      => addr_v := 19;
                when 10     => addr_v := 15;
                when 11     => addr_v := 11;
                when 12     => addr_v := 7;
                when 13     => addr_v := 3;
                when 14     => addr_v := 3;
                when others => addr_v := 11;
            end case;
        end if;

        return std_logic_vector(to_unsigned(addr_v, 5));
    end function;

    -- Certain byte positions are already correctly aligned at the SRL input and
    -- are cheaper to bypass than to read through the SRL tap.
    function bypass_for_state(
        idx          : integer range 0 to 15;
        inverse_mode : std_logic
    ) return std_logic is
    begin
        if support_inverse and (inverse_mode = '1') then
            if idx = 13 then
                return '1';
            end if;
        elsif idx = 15 then
            return '1';
        end if;

        return '0';
    end function;

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                -- Reset restarts the 16-byte sequence and reloads the initial
                -- tap for the selected direction.
                state    <= 0;
                tap_addr <= initial_addr(inverse);
                done_reg <= '0';
            else
                done_reg <= '0';

                if ce = '1' then
                    -- Update the tap for the next byte position and advance the
                    -- byte counter once per valid serial input byte.
                    tap_addr <= next_addr_for_state(state, inverse);

                    if state = 15 then
                        state <= 0;
                    else
                        state <= state + 1;
                    end if;

                    -- done is asserted once the SRL history is sufficiently
                    -- primed for the encrypt controller to launch MixColumns.
                    if state = 10 then
                        done_reg <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Select either the bypassed current byte or the delayed SRL output,
    -- depending on which is correct for the present state index.
    state_out <= state_in when bypass_for_state(state, inverse) = '1' else srl_out;
    done      <= done_reg;

    -- Eight parallel SRLs carry the eight bits of each byte. The datapath
    -- therefore scales with byte width only, not with full AES state width.
    gen_srl : for i in 0 to 7 generate
    begin
        SRLC32E_inst : SRLC32E
            generic map (
                INIT => X"00000000"
            )
            port map (
                Q   => srl_out(i),
                A   => tap_addr,
                CE  => ce,
                CLK => clk,
                D   => state_in(i)
            );
    end generate gen_srl;

end Behavioral;
