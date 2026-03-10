------------------------------------------------------------------------------
-- Company: University of Sheffield
-- Engineer: Cian Thomson
--
-- Create Date: 19.02.2026 18:56:01
-- Module Name: sbox_cf
-- Project Name: aes
-- Description:
--   Composite-field AES S-box / inverse S-box.
--   The substitution is implemented algorithmically rather than as a 256-entry
--   lookup table, reducing memory usage and fitting the low-area serial AES
--   architecture used elsewhere in this design.
--
-- Dependencies:
--   N/A
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

------------------------------------------------------------------------------
-- Byte-wide AES substitution primitive
------------------------------------------------------------------------------
entity aes_sbox_cf is
    port (
        byte_in  : in  std_logic_vector(7 downto 0); -- Input byte
        usage    : in  std_logic;                    -- '0' = forward S-box, '1' = inverse S-box
        byte_out : out std_logic_vector(7 downto 0)
    );
end entity;

------------------------------------------------------------------------------
-- Composite-field implementation:
--   polynomial basis -> isomorphic map -> GF((2^4)^2) inversion ->
--   inverse map -> affine transform
------------------------------------------------------------------------------
architecture rtl of aes_sbox_cf is

    --------------------------------------------------------------------------
    -- Type definitions used to decompose GF(2^8) arithmetic
    --------------------------------------------------------------------------
    subtype byte   is std_logic_vector(7 downto 0);
    subtype nibble is std_logic_vector(3 downto 0);
    subtype crumb  is std_logic_vector(1 downto 0);
    type mat8_t is array (0 to 7) of byte; -- 8x8 binary matrix, LSB-first

    --------------------------------------------------------------------------
    -- Constants for the selected composite-field basis
    --------------------------------------------------------------------------
    constant PHI    : crumb  := "10";
    constant LAMBDA : nibble := x"C";

    --------------------------------------------------------------------------
    -- Basis-change matrices from the chosen composite-field mapping
    --------------------------------------------------------------------------
    -- Synthesis reduces these constant matrices to XOR networks.
    constant DELTA : mat8_t := (
        0 => (0 => '1', 1 => '1', 6 => '1', others => '0'),  -- [1,1,0,0,0,0,1,0]
        1 => (1 => '1', 4 => '1', 6 => '1', others => '0'),  -- [0,1,0,0,1,0,1,0]
        2 => (1 => '1', 2 => '1', 3 => '1', 4 => '1', 7 => '1', others => '0'),  -- [0,1,1,1,1,0,0,1]
        3 => (1 => '1', 2 => '1', 6 => '1', 7 => '1', others => '0'),  -- [0,1,1,0,0,0,1,1]
        4 => (1 => '1', 2 => '1', 3 => '1', 5 => '1', 7 => '1', others => '0'),  -- [0,1,1,1,0,1,0,1]
        5 => (2 => '1', 3 => '1', 5 => '1', 7 => '1', others => '0'),  -- [0,0,1,1,0,1,0,1]
        6 => (1 => '1', 2 => '1', 3 => '1', 4 => '1', 6 => '1', 7 => '1', others => '0'),  -- [0,1,1,1,1,0,1,1]
        7 => (5 => '1', 7 => '1', others => '0')  -- [0,0,0,0,0,1,0,1]
    );

    constant DELTA_INV : mat8_t := (
        0 => (0 => '1', 2 => '1', 4 => '1', 5 => '1', 6 => '1', others => '0'),  -- [1,0,1,0,1,1,1,0]
        1 => (4 => '1', 5 => '1', others => '0'),  -- [0,0,0,0,1,1,0,0]
        2 => (1 => '1', 2 => '1', 3 => '1', 4 => '1', 7 => '1', others => '0'),  -- [0,1,1,1,1,0,0,1]
        3 => (1 => '1', 2 => '1', 3 => '1', 4 => '1', 5 => '1', others => '0'),  -- [0,1,1,1,1,1,0,0]
        4 => (1 => '1', 2 => '1', 4 => '1', 5 => '1', 6 => '1', others => '0'),  -- [0,1,1,0,1,1,1,0]
        5 => (1 => '1', 5 => '1', 6 => '1', others => '0'),  -- [0,1,0,0,0,1,1,0]
        6 => (2 => '1', 6 => '1', others => '0'),  -- [0,0,1,0,0,0,1,0]
        7 => (1 => '1', 5 => '1', 6 => '1', 7 => '1', others => '0')  -- [0,1,0,0,0,1,1,1]
    );

    --------------------------------------------------------------------------
    -- AES affine transform and its inverse from FIPS-197, LSB-first
    --------------------------------------------------------------------------
    constant AFFINE_M : mat8_t := (
        0 => (0 => '1', 4 => '1', 5 => '1', 6 => '1', 7 => '1', others => '0'),  -- [1,1,1,1,0,0,0,1]
        1 => (0 => '1', 1 => '1', 5 => '1', 6 => '1', 7 => '1', others => '0'),  -- [1,1,1,0,0,0,1,1]
        2 => (0 => '1', 1 => '1', 2 => '1', 6 => '1', 7 => '1', others => '0'),  -- [1,1,0,0,0,1,1,1]
        3 => (0 => '1', 1 => '1', 2 => '1', 3 => '1', 7 => '1', others => '0'),  -- [1,0,0,0,1,1,1,1]
        4 => (0 => '1', 1 => '1', 2 => '1', 3 => '1', 4 => '1', others => '0'),  -- [0,0,0,1,1,1,1,1]
        5 => (1 => '1', 2 => '1', 3 => '1', 4 => '1', 5 => '1', others => '0'),  -- [0,0,1,1,1,1,1,0]
        6 => (2 => '1', 3 => '1', 4 => '1', 5 => '1', 6 => '1', others => '0'),  -- [0,1,1,1,1,1,0,0]
        7 => (3 => '1', 4 => '1', 5 => '1', 6 => '1', 7 => '1', others => '0')  -- [1,1,1,1,1,0,0,0]
    );

    constant AFFINE_INV_M : mat8_t := (
        0 => (2 => '1', 5 => '1', 7 => '1', others => '0'),  -- [0,0,1,0,0,1,0,1]
        1 => (0 => '1', 3 => '1', 6 => '1', others => '0'),  -- [1,0,0,1,0,0,1,0]
        2 => (1 => '1', 4 => '1', 7 => '1', others => '0'),  -- [0,1,0,0,1,0,0,1]
        3 => (0 => '1', 2 => '1', 5 => '1', others => '0'),  -- [1,0,1,0,0,1,0,0]
        4 => (1 => '1', 3 => '1', 6 => '1', others => '0'),  -- [0,1,0,1,0,0,1,0]
        5 => (2 => '1', 4 => '1', 7 => '1', others => '0'),  -- [0,0,1,0,1,0,0,1]
        6 => (0 => '1', 3 => '1', 5 => '1', others => '0'),  -- [1,0,0,1,0,1,0,0]
        7 => (1 => '1', 4 => '1', 6 => '1', others => '0')  -- [0,1,0,0,1,0,1,0]
    );

    --------------------------------------------------------------------------
    -- GF(2) matrix-vector multiply
    --------------------------------------------------------------------------
    function mat_vec_mul(
        m : mat8_t;
        v : byte
    ) return byte is
        -- r accumulates the output vector; s accumulates one row dot product.
        variable r : byte := (others => '0');
        variable s : std_logic;
    begin
        for i in 0 to 7 loop
            s := '0';

            for j in 0 to 7 loop
                -- In GF(2), multiplication is AND and addition is XOR.
                s := s xor (m(i)(j) and v(j));
            end loop;

            r(i) := s;
        end loop;

        return r;
    end function;

    --------------------------------------------------------------------------
    -- Basis transforms
    --------------------------------------------------------------------------
    function iso_map(
        b : byte
    ) return byte is
    begin
        return mat_vec_mul(DELTA, b);
    end function;

    function inv_iso_map(
        b : byte
    ) return byte is
    begin
        return mat_vec_mul(DELTA_INV, b);
    end function;

    --------------------------------------------------------------------------
    -- Affine transforms
    --------------------------------------------------------------------------
    function affine_transform(
        b : byte
    ) return byte is
    begin
        return mat_vec_mul(AFFINE_M, b) xor x"63";
    end function;

    function inverse_affine_transform(
        b : byte
    ) return byte is
    begin
        return mat_vec_mul(AFFINE_INV_M, (b xor x"63"));
    end function;

    --------------------------------------------------------------------------
    -- GF(2^2) arithmetic
    --------------------------------------------------------------------------
    function gf2_2_mul(
        a : crumb;
        b : crumb
    ) return crumb is
        variable p     : unsigned(2 downto 0) := (others => '0');
        variable aa    : unsigned(2 downto 0) := ("0" & unsigned(a));
        variable bb    : unsigned(1 downto 0) := unsigned(b);
        variable carry : std_logic;
    begin
        for k in 0 to 1 loop
            if bb(0) = '1' then
                p := p xor aa;
            end if;

            carry := aa(1);
            aa    := aa sll 1;

            if carry = '1' then
                aa := aa xor "111";
            end if;

            bb := bb srl 1;
        end loop;

        return std_logic_vector(p(1 downto 0));
    end function;

    --------------------------------------------------------------------------
    -- GF(2^4) arithmetic over GF(2^2)
    --------------------------------------------------------------------------
    function gf4_mul(
        a : nibble;
        b : nibble
    ) return nibble is
        variable a1, a0 : crumb;
        variable b1, b0 : crumb;
        variable t11, t10, t01, t00 : crumb;
        variable out1, out0 : crumb;
    begin
        a1 := a(3 downto 2);
        a0 := a(1 downto 0);
        b1 := b(3 downto 2);
        b0 := b(1 downto 0);

        t11 := gf2_2_mul(a1, b1);
        t10 := gf2_2_mul(a1, b0);
        t01 := gf2_2_mul(a0, b1);
        t00 := gf2_2_mul(a0, b0);

        -- Apply the reduction x^2 = x + PHI.
        out1 := t11 xor t10 xor t01;
        out0 := gf2_2_mul(t11, PHI) xor t00;

        return nibble'(out1 & out0);
    end function;

    function gf4_square(
        a : nibble
    ) return nibble is
    begin
        return gf4_mul(a, a);
    end function;

    function gf4_inv(
        a : nibble
    ) return nibble is
        variable a2, a4, a8, a12, a14 : nibble;
    begin
        if a = "0000" then
            return "0000";
        end if;

        a2  := gf4_square(a);    -- a^2
        a4  := gf4_square(a2);   -- a^4
        a8  := gf4_square(a4);   -- a^8
        a12 := gf4_mul(a8, a4);  -- a^12
        a14 := gf4_mul(a12, a2); -- a^14

        return a14;
    end function;

    --------------------------------------------------------------------------
    -- GF(2^8) inversion in the composite-field representation
    --------------------------------------------------------------------------
    function gf8_inv_composite(
        b : byte
    ) return byte is
        variable a1, a0 : nibble;
        variable d, d_inv : nibble;
        variable b1, b0 : nibble;
    begin
        if b = x"00" then
            return x"00";
        end if;

        a1 := b(7 downto 4);
        a0 := b(3 downto 0);

        -- Determinant of the 2x2 composite-field representation.
        d := gf4_mul(a0, (a0 xor a1)) xor gf4_mul(gf4_square(a1), LAMBDA);
        d_inv := gf4_inv(d);

        b1 := gf4_mul(a1, d_inv);
        b0 := gf4_mul((a0 xor a1), d_inv);

        return byte'(b1 & b0);
    end function;

    --------------------------------------------------------------------------
    -- Forward and inverse AES S-box functions
    --------------------------------------------------------------------------
    function sbox_fwd(
        b : byte
    ) return byte is
        variable x : byte;
    begin
        x := iso_map(b);
        x := gf8_inv_composite(x);
        x := inv_iso_map(x);
        x := affine_transform(x);
        return x;
    end function;

    function sbox_inv(
        b : byte
    ) return byte is
        variable x : byte;
    begin
        x := inverse_affine_transform(b);
        x := iso_map(x);
        x := gf8_inv_composite(x);
        x := inv_iso_map(x);
        return x;
    end function;

begin

    -- Pure combinational selection between forward and inverse substitution.
    process (byte_in, usage)
    begin
        if usage = '1' then
            byte_out <= sbox_inv(byte_in);
        else
            byte_out <= sbox_fwd(byte_in);
        end if;
    end process;

end architecture;
