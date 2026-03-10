------------------------------------------------------------------------------
-- Company: University of Sheffield
-- Engineer: Cian Thomson
-- 
-- Create Date: 19.02.2026 18:56:01
-- Module Name: sbox_cf
-- Project Name: aes
-- Description: 
-- Algorithmic sbox for reduced area 
--
-- Dependencies: 
-- N/A
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

-- Defintions of the s-box inputs with the agreed format.
entity aes_sbox_cf is
    port(
        -- Input to the sbox (byte)
        byte_in  : in  std_logic_vector(7 downto 0);
        -- Flag for usage: '0' = SBOX, '1' = INV_SBOX
        usage  : in  std_logic;
        -- Output of the sbox (byte)
        byte_out : out std_logic_vector(7 downto 0)
    );
end entity;

------------------------------------------------------------------------------

-- Architecture for opertation of the alogrithmic aes sbox using composite field
architecture rtl of aes_sbox_cf is
 
    ---------------------------------------------------------------------------
    -- Type definitions for comopsit field breakdown 
    ---------------------------------------------------------------------------
    -- Byte: 8-bit
    subtype byte   is std_logic_vector(7 downto 0);
    -- Nibble: 4-bit
    subtype nibble is std_logic_vector(3 downto 0);
    -- Crumb: 2-bit
    subtype crumb  is std_logic_vector(1 downto 0);  
    -- 8 byte matrix type for the inverse and delta declorations (LSB-first)
    type mat8_t is array (0 to 7) of byte;
 
    ---------------------------------------------------------------------------
    -- Constant definitions for composit field multiplications
    ---------------------------------------------------------------------------   
    constant PHI : crumb := "10";
    constant LAMBDA : nibble := x"C";

    ---------------------------------------------------------------------------
    -- Delta and inverse delata definitions (constant) from Zhang et al. paper
    ---------------------------------------------------------------------------
    
    -- !NOTE: THIS CAN BE FURTHER SIMPLIFIED WITH XOR NETWORK!
    
    -- Delta of 8x8-bit matrix
    constant DELTA : mat8_t := (
        0 => (0=>'1',1=>'1',6=>'1', others=>'0'),  -- [1,1,0,0,0,0,1,0]
        1 => (1=>'1',4=>'1',6=>'1', others=>'0'),  -- [0,1,0,0,1,0,1,0]
        2 => (1=>'1',2=>'1',3=>'1',4=>'1',7=>'1', others=>'0'),  -- [0,1,1,1,1,0,0,1]
        3 => (1=>'1',2=>'1',6=>'1',7=>'1', others=>'0'),  -- [0,1,1,0,0,0,1,1]
        4 => (1=>'1',2=>'1',3=>'1',5=>'1',7=>'1', others=>'0'),  -- [0,1,1,1,0,1,0,1]
        5 => (2=>'1',3=>'1',5=>'1',7=>'1', others=>'0'),  -- [0,0,1,1,0,1,0,1]
        6 => (1=>'1',2=>'1',3=>'1',4=>'1',6=>'1',7=>'1', others=>'0'),  -- [0,1,1,1,1,0,1,1]
        7 => (5=>'1',7=>'1', others=>'0')  -- [0,0,0,0,0,1,0,1]
    );
    
    -- Inverse delta of 8x8-bit matrix over GF(2)
    constant DELTA_INV : mat8_t := (
        0 => (0=>'1',2=>'1',4=>'1',5=>'1',6=>'1', others=>'0'),  -- [1,0,1,0,1,1,1,0]
        1 => (4=>'1',5=>'1', others=>'0'),  -- [0,0,0,0,1,1,0,0]
        2 => (1=>'1',2=>'1',3=>'1',4=>'1',7=>'1', others=>'0'), -- [0,1,1,1,1,0,0,1]
        3 => (1=>'1',2=>'1',3=>'1',4=>'1',5=>'1', others=>'0'), -- [0,1,1,1,1,1,0,0]
        4 => (1=>'1',2=>'1',4=>'1',5=>'1',6=>'1', others=>'0'), -- [0,1,1,0,1,1,1,0]
        5 => (1=>'1',5=>'1',6=>'1', others=>'0'),  -- [0,1,0,0,0,1,1,0]
        6 => (2=>'1',6=>'1', others=>'0'),  -- [0,0,1,0,0,0,1,0]
        7 => (1=>'1',5=>'1',6=>'1',7=>'1', others=>'0')  -- [0,1,0,0,0,1,1,1]
    );  

    ---------------------------------------------------------------------------
    -- AES affine matrix and inverse (LSB-first) FIPs-197
    ---------------------------------------------------------------------------
    constant AFFINE_M : mat8_t := (
        0 => (0=>'1',4=>'1',5=>'1',6=>'1',7=>'1', others=>'0'),  -- [1,1,1,1,0,0,0,1]
        1 => (0=>'1',1=>'1',5=>'1',6=>'1',7=>'1', others=>'0'),  -- [1,1,1,0,0,0,1,1]
        2 => (0=>'1',1=>'1',2=>'1',6=>'1',7=>'1', others=>'0'),  -- [1,1,0,0,0,1,1,1]
        3 => (0=>'1',1=>'1',2=>'1',3=>'1',7=>'1', others=>'0'),  -- [1,0,0,0,1,1,1,1]
        4 => (0=>'1',1=>'1',2=>'1',3=>'1',4=>'1', others=>'0'),  -- [0,0,0,1,1,1,1,1]
        5 => (1=>'1',2=>'1',3=>'1',4=>'1',5=>'1', others=>'0'),  -- [0,0,1,1,1,1,1,0]
        6 => (2=>'1',3=>'1',4=>'1',5=>'1',6=>'1', others=>'0'),  -- [0,1,1,1,1,1,0,0]
        7 => (3=>'1',4=>'1',5=>'1',6=>'1',7=>'1', others=>'0')  -- [1,1,1,1,1,0,0,0]
    );

    constant AFFINE_INV_M : mat8_t := (
        0 => (2=>'1',5=>'1',7=>'1', others=>'0'),  -- [0,0,1,0,0,1,0,1]
        1 => (0=>'1',3=>'1',6=>'1', others=>'0'),  -- [1,0,0,1,0,0,1,0]
        2 => (1=>'1',4=>'1',7=>'1', others=>'0'),  -- [0,1,0,0,1,0,0,1]
        3 => (0=>'1',2=>'1',5=>'1', others=>'0'),  -- [1,0,1,0,0,1,0,0]
        4 => (1=>'1',3=>'1',6=>'1', others=>'0'),  -- [0,1,0,1,0,0,1,0]
        5 => (2=>'1',4=>'1',7=>'1', others=>'0'),  -- [0,0,1,0,1,0,0,1]
        6 => (0=>'1',3=>'1',5=>'1', others=>'0'),  -- [1,0,0,1,0,1,0,0]
        7 => (1=>'1',4=>'1',6=>'1', others=>'0')  -- [0,1,0,0,1,0,1,0]
    );  

    ---------------------------------------------------------------------------
    -- GF(2) matrix-vector multiply: 8×8 binary matrix with an 8-bit vector
    ---------------------------------------------------------------------------
    function mat_vec_mul(
    m : mat8_t; 
    v : byte
    ) return byte is
    
        -- Result and accumulator variables for vecto and dot product
        variable r : byte := (others => '0');
        variable s : std_logic;
        
    begin
        
        -- For each of the output bits
        for i in 0 to 7 loop
            
            -- Initlisise the accumulator to zero for each cycle
            s := '0';
            
            -- Perform the dot product for each element
            for j in 0 to 7 loop
            
                -- GF(2): AND = multplication, XOR = addition
                s := s xor (m(i)(j) and v(j));
                
            end loop;
            
            -- Assigm ith bit as output accumulator for given cycle
            r(i) := s;
            
        end loop;
        
        return r;
        
    end function;

    ---------------------------------------------------------------------------
    -- Isomorphic transformation from GF(2^8) to GF((2^4)^2)
    ---------------------------------------------------------------------------
    function iso_map(
    b : byte
    ) return byte is
    begin
    
        -- Matrix multiplication of byte with delta
        return mat_vec_mul(DELTA, b);
        
    end function;
    
    ---------------------------------------------------------------------------
    -- Inverse isomorphic transformation GF((2^4)^2) back to GF(2^8)
    ---------------------------------------------------------------------------
    function inv_iso_map(
    b : byte
    ) return byte is
    begin
        
        -- Matrix multiplication of byte with inverse delta
        return mat_vec_mul(DELTA_INV, b);
        
    end function;

    ---------------------------------------------------------------------------
    -- Applies the fixed affine transformation defined in FIPs-197
    ---------------------------------------------------------------------------
    function affine_transform(
    b : byte
    ) return byte is
    begin
    
        -- Matrix multiplication of byte with affine XORed with constant  
        return mat_vec_mul(AFFINE_M, b) xor x"63";
    
    end function;

    ---------------------------------------------------------------------------
    -- Applies the inverse affine transformation defined in FIPs-197
    ---------------------------------------------------------------------------
    function inverse_affine_transform(
    b : byte
    ) return byte is
    begin
        
        -- XORed byte then matrix multiplied with inverse affine hence opposite
        return mat_vec_mul(AFFINE_INV_M, (b xor x"63"));
    
    end function;

    ---------------------------------------------------------------------------
    -- GF(2^2) multiply with irreducable polynomial x^2 + x + 1
    ---------------------------------------------------------------------------
    function gf2_2_mul(
    a, b : crumb
    ) return crumb is
        
        -- Product accumunlation variable initilised to 000
        variable p  : unsigned(2 downto 0) := (others => '0');
        -- Multiplicand vairable extended from input 'a' now 3-bit
        variable aa : unsigned(2 downto 0) := ("0" & unsigned(a));
        -- Multiplier variable initilised with input 'b'
        variable bb : unsigned(1 downto 0) := unsigned(b);
        -- MSB variable for reduction
        variable carry : std_logic;
        
    begin
    
        -- Repeate twice, for each bit in 'b'
        for k in 0 to 1 loop
        
            -- If the LSB of multiplier is 1
            if bb(0) = '1' then
            
                -- Add the multiplicand to the product
                p := p xor aa;
                
            end if;
            
            -- Check if x^2 term will appear after shift
            carry := aa(1);
            
            -- Multiply by x
            aa := aa sll 1;
            
            -- Reduce modulo m(x) = x^2 +x + 1 if there is overflow
            if carry = '1' then
            
                aa := aa xor "111";
                
            end if;
            
            -- Shift multiplier
            bb := bb srl 1;
            
        end loop;
        
        -- Return lower 2-bits as the result
        return std_logic_vector(p(1 downto 0));
        
    end function;

    ---------------------------------------------------------------------------
    -- GF(2^4) multiplication over GF(2^2) using p(x) = x^2 + x + PHI
    ---------------------------------------------------------------------------
    function gf4_mul(
    a, b : nibble
    ) return nibble is
        
        -- Split the inputs into GF(2^2) components:
        -- a = (a_1)x + (a_0)
        -- b = (b_1)x + (b_0)
        variable a1,a0 : crumb;
        variable b1,b0 : crumb;
        -- Initilise partial product variables
        variable t11,t10,t01,t00 : crumb;
        -- Initilise the output coefficients in GF(2^2)
        variable out1,out0 : crumb;
        
    begin
        
        -- Extract the high/low GF(2^2) components
        a1 := a(3 downto 2);
        a0 := a(1 downto 0);
        b1 := b(3 downto 2);
        b0 := b(1 downto 0);

        -- Compute their partial products
        t11 := gf2_2_mul(a1, b1);
        t10 := gf2_2_mul(a1, b0);
        t01 := gf2_2_mul(a0, b1);
        t00 := gf2_2_mul(a0, b0);

        -- Apply a modular reduction using (x^2 = x + PHI)
        out1 := t11 xor t10 xor t01;
        out0 := gf2_2_mul(t11, PHI) xor t00;

        -- Concatinate the GF(2^2) coeffients to a GF(2^4) result
        return out1 & out0;
        
    end function;

    ---------------------------------------------------------------------------
    -- GF(2^4) squaring via passing duplicate inputs to the GF(2^4) multiplier
    ---------------------------------------------------------------------------
    function gf4_square(
    a : nibble
    ) return nibble is
    begin
    
        -- Pass same input to the GF(2^4) multiplier
        return gf4_mul(a, a);
        
    end function;

    ---------------------------------------------------------------------------
    -- GF(2^4) multiplicative inverse of non-zero elements
    ---------------------------------------------------------------------------
    function gf4_inv(
    a : nibble
    ) return nibble is
        
        -- Initilise alpha squared terms and multiples as nibbles (4-bit)
        variable a2, a4, a8, a12, a14 : nibble;
    
    begin
    
        -- Checking for zero term i.e. no multiplicative inverse exsists
        if a = "0000" then
        
            -- Return '0000' no no undefined state is obtained
            return "0000";
            
        end if;

        -- Compute successive powers using the squaring
        a2  := gf4_square(a);     -- a^2
        a4  := gf4_square(a2);    -- a^4
        a8  := gf4_square(a4);    -- a^8
        
        -- Compute a^12 via mupltiplication (power addition)
        a12 := gf4_mul(a8, a4);   -- a^12
        
        -- Compute a^-1 term
        a14 := gf4_mul(a12, a2);  -- a^14
    
        return a14;
        
    end function;

    ---------------------------------------------------------------------------
    -- GF(2^8) composite inverse to GF((2^4)^2) using LAMBDA
    ---------------------------------------------------------------------------
    function gf8_inv_composite(
    b : byte
    ) return byte is
    
        -- Split the input into GF(2^4) coefficients:
        -- b = (a_1)x + (a_0)
        variable a1,a0 : nibble;
        -- Intermediate determinant and its inverse
        variable d, d_inv : nibble;
        -- Output coeffcinets in GF(2^4)
        variable b1,b0 : nibble;
        
    begin
    
        -- If zero, it has no multiplactive inverse
        if b = x"00" then
        
            -- Hence, return '0x00'
            return x"00";
            
        end if;

        -- Extract the GF(2^4) components
        a1 := b(7 downto 4);
        a0 := b(3 downto 0);

        -- Compute determinant as seen in Zhang et al fig 3
        d := gf4_mul(a0, (a0 xor a1)) xor gf4_mul(gf4_square(a1), LAMBDA);
        
        -- Invert the determinant in GF(2^4)
        d_inv := gf4_inv(d);

        -- Compute the inverse coefficients
        b1 := gf4_mul(a1, d_inv);
        b0 := gf4_mul((a0 xor a1), d_inv);

        -- Concatinate into the GF(2^8) element
        return b1 & b0;
        
    end function;

    ---------------------------------------------------------------------------
    -- Forward aes sbox (composite-field implementation)
    ---------------------------------------------------------------------------
    function sbox_fwd(
    b : byte
    ) return byte is
    
        -- Initilise operation variable x as byte (8-bit subsystem)
        variable x : byte;
        
    begin
    
        -- Change the basis using delta
        x := iso_map(b);
        
        -- Composite field inversion in GF(2^8)
        x := gf8_inv_composite(x);
        
        -- Return to polynomial basis using inverse delta
        x := inv_iso_map(x);
        
        -- Apply the aes affine transformation
        x := affine_transform(x);
        
        -- Return the output of the processes
        return x;
        
    end function;

    ---------------------------------------------------------------------------
    -- Inverse sbox implimentation (composite field)
    ---------------------------------------------------------------------------
  
    function sbox_inv(
    b : byte
    ) return byte is
    
        -- Initilise operation variable x as byte (8-bit subsystem)
        variable x : byte;
        
    begin
    
        -- Undo the affine transfromation
        x := inverse_affine_transform(b);
        
        -- Change basis using delta
        x := iso_map(x);
        
        -- Perform the composite field inversion
        x := gf8_inv_composite(x);
        
        -- Return to the polynimial bais using inverse delta
        x := inv_iso_map(x);
        
        -- Return outpit of the processes
        return x;
        
    end function;

------------------------------------------------------------------------------

begin

    -- Process that takes the input to the decvice along with the usage
    process(byte_in, usage)
    
    begin
        
        -- If the usage is for inverse then call respective function
        if usage = '1' then
        
        
            byte_out <= sbox_inv(byte_in);
        
        -- Else we require a normal subsitution
        else
        
            byte_out <= sbox_fwd(byte_in);
            
        end if;
        
    end process;

end architecture;