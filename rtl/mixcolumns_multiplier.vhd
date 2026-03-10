----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 02.03.2026 16:31:54
-- Design Name:
-- Module Name: mixcolumns_multiplier - Behavioral
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
-- mixcolumns_multiplier.vhd
-- Based on: "Design and Implementation of Low-area and Low-power AES
--            Encryption Hardware Core", Hamalainen et al., EUROMICRO DSD'06
--
-- Byte-serial MixColumns / InvMixColumns engine.
-- One input byte is accepted per cycle. The contribution of each input byte to
-- the four output bytes is accumulated over four cycles, so a full 32-bit AES
-- column is produced without instantiating four independent matrix multipliers.
-- The same accumulator structure is reused for both MixColumns and
-- InvMixColumns. Only the byte coefficients change when inverse = '1'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package aes_mixcolumns_pkg is
    -- Returns the four partial products contributed by one input byte at a
    -- given byte position within the AES column.
    function mixcolumns_term(
        d_in         : std_logic_vector(7 downto 0);
        byte_pos     : integer range 0 to 3;
        inverse_mode : std_logic
    ) return std_logic_vector;

    -- Pure combinational full-column transform used by the decrypt path and
    -- testbench reference checks.
    function mixcolumns_transform(
        col_in       : std_logic_vector(31 downto 0);
        inverse_mode : std_logic
    ) return std_logic_vector;
end package aes_mixcolumns_pkg;

package body aes_mixcolumns_pkg is
    subtype byte_t is std_logic_vector(7 downto 0);
    type byte_array4_t is array (0 to 3) of byte_t;
    type coeff_row_t is array (0 to 3) of integer range 1 to 14;
    type coeff_matrix_t is array (0 to 3) of coeff_row_t;

    -- Forward and inverse AES column matrices expressed as GF(2^8) constants.
    constant MIX_MATRIX_FWD : coeff_matrix_t := (
        (2, 3, 1, 1),
        (1, 2, 3, 1),
        (1, 1, 2, 3),
        (3, 1, 1, 2)
    );

    constant MIX_MATRIX_INV : coeff_matrix_t := (
        (14, 11, 13, 9),
        (9, 14, 11, 13),
        (13, 9, 14, 11),
        (11, 13, 9, 14)
    );

    -- Multiply by x in GF(2^8) modulo the AES polynomial.
    function xtime(a : byte_t) return byte_t is
        variable r : byte_t;
    begin
        r := a(6 downto 0) & '0';
        if a(7) = '1' then
            r := r xor x"1B";
        end if;
        return r;
    end function;

    -- Small shared constant multiplier. Precomputing x2/x4/x8 lets all AES
    -- coefficients used by MixColumns/InvMixColumns be formed with XOR only.
    function mul_by_const(
        a     : byte_t;
        coeff : integer range 1 to 14
    ) return byte_t is
        variable x2 : byte_t;
        variable x4 : byte_t;
        variable x8 : byte_t;
    begin
        x2 := xtime(a);
        x4 := xtime(x2);
        x8 := xtime(x4);

        case coeff is
            when 1 =>
                return a;
            when 2 =>
                return x2;
            when 3 =>
                return x2 xor a;
            when 9 =>
                return x8 xor a;
            when 11 =>
                return x8 xor x2 xor a;
            when 13 =>
                return x8 xor x4 xor a;
            when others =>
                return x8 xor x4 xor x2;
        end case;
    end function;

    -- Convert a packed 32-bit column into byte-array form.
    function unpack_column(
        col_in : std_logic_vector(31 downto 0)
    ) return byte_array4_t is
        variable result : byte_array4_t;
    begin
        result(0) := col_in(31 downto 24);
        result(1) := col_in(23 downto 16);
        result(2) := col_in(15 downto 8);
        result(3) := col_in(7 downto 0);
        return result;
    end function;

    -- Pack four bytes back into AES column order.
    function pack_column(
        col_in : byte_array4_t
    ) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0);
    begin
        result(31 downto 24) := col_in(0);
        result(23 downto 16) := col_in(1);
        result(15 downto 8)  := col_in(2);
        result(7 downto 0)   := col_in(3);
        return result;
    end function;

    -- Select the required coefficient from the forward or inverse matrix.
    function coeff_for(
        out_idx      : integer range 0 to 3;
        byte_pos     : integer range 0 to 3;
        inverse_mode : std_logic
    ) return integer is
    begin
        if inverse_mode = '1' then
            return MIX_MATRIX_INV(out_idx)(byte_pos);
        end if;

        return MIX_MATRIX_FWD(out_idx)(byte_pos);
    end function;

    -- Compute one byte contribution to all four output rows.
    function mixcolumns_term(
        d_in         : std_logic_vector(7 downto 0);
        byte_pos     : integer range 0 to 3;
        inverse_mode : std_logic
    ) return std_logic_vector is
        variable result : byte_array4_t;
    begin
        for out_idx in 0 to 3 loop
            result(out_idx) := mul_by_const(
                d_in,
                coeff_for(out_idx, byte_pos, inverse_mode)
            );
        end loop;

        return pack_column(result);
    end function;

    -- Reference full-column implementation built from four mixcolumns_term calls.
    function mixcolumns_transform(
        col_in       : std_logic_vector(31 downto 0);
        inverse_mode : std_logic
    ) return std_logic_vector is
        variable in_col  : byte_array4_t;
        variable out_col : byte_array4_t := (others => (others => '0'));
        variable term_v  : std_logic_vector(31 downto 0);
    begin
        in_col := unpack_column(col_in);

        for byte_pos in 0 to 3 loop
            term_v := mixcolumns_term(in_col(byte_pos), byte_pos, inverse_mode);
            out_col(0) := out_col(0) xor term_v(31 downto 24);
            out_col(1) := out_col(1) xor term_v(23 downto 16);
            out_col(2) := out_col(2) xor term_v(15 downto 8);
            out_col(3) := out_col(3) xor term_v(7 downto 0);
        end loop;

        return pack_column(out_col);
    end function;
end package body aes_mixcolumns_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mixcolumns_multiplier is
    generic (
        support_inverse : boolean := true
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        en      : in  std_logic;  -- Pulse high on the first byte of a new column
        inverse : in  std_logic := '0';               -- '1' selects InvMixColumns coefficients
        d_in    : in  std_logic_vector(7 downto 0);   -- Byte stream for one AES column
        d0_out  : out std_logic_vector(7 downto 0);   -- Output column byte 0
        d1_out  : out std_logic_vector(7 downto 0);   -- Output column byte 1
        d2_out  : out std_logic_vector(7 downto 0);   -- Output column byte 2
        d3_out  : out std_logic_vector(7 downto 0)    -- Output column byte 3
    );
end entity mixcolumns_multiplier;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.aes_mixcolumns_pkg.all;

architecture rtl of mixcolumns_multiplier is
    -- Four-byte running accumulator for the current column result.
    signal R0, R1, R2, R3 : std_logic_vector(7 downto 0) := (others => '0');
    -- Tracks which input byte position is currently being accumulated.
    signal t : unsigned(1 downto 0) := (others => '0');
    -- High while bytes 1..3 of the current column are still being processed.
    signal active : std_logic := '0';

begin
    process(clk)
        variable term_v         : std_logic_vector(31 downto 0);
        variable inverse_mode_v : std_logic;
    begin
        if rising_edge(clk) then
            -- Gate inverse support so an encrypt-only build can prune the
            -- additional coefficient selection logic.
            if support_inverse and (inverse = '1') then
                inverse_mode_v := '1';
            else
                inverse_mode_v := '0';
            end if;

            if rst = '1' then
                -- Reset clears the accumulators and returns the block to the
                -- idle state ready for the first byte of a new column.
                R0 <= (others => '0');
                R1 <= (others => '0');
                R2 <= (others => '0');
                R3 <= (others => '0');
                t  <= (others => '0');
                active <= '0';
            elsif en = '1' then
                -- Start of a new column. Load the partial products for byte 0
                -- directly into the accumulators and mark the engine active for
                -- the remaining three bytes.
                term_v := mixcolumns_term(d_in, 0, inverse_mode_v);
                R0 <= term_v(31 downto 24);
                R1 <= term_v(23 downto 16);
                R2 <= term_v(15 downto 8);
                R3 <= term_v(7 downto 0);
                t <= "01";
                active <= '1';
            elsif active = '1' then
                -- Subsequent bytes are XOR-accumulated into the running result.
                -- This serial accumulation is the key area-saving trade-off.
                term_v := mixcolumns_term(d_in, to_integer(t), inverse_mode_v);
                R0 <= R0 xor term_v(31 downto 24);
                R1 <= R1 xor term_v(23 downto 16);
                R2 <= R2 xor term_v(15 downto 8);
                R3 <= R3 xor term_v(7 downto 0);

                if t = "11" then
                    -- After byte 3 the output column is complete and remains on
                    -- the registers until the next column starts.
                    t <= (others => '0');
                    active <= '0';
                else
                    t <= t + 1;
                end if;
            end if;
        end if;
    end process;

    d0_out <= R0;
    d1_out <= R1;
    d2_out <= R2;
    d3_out <= R3;

end architecture rtl;
