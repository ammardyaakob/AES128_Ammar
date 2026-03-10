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
--            Encryption Hardware Core", Hämäläinen et al., EUROMICRO DSD'06
--
-- Section 4.2 + Figure 4 implementation.
--
-- One AES State column [x0, x1, x2, x3] is fed byte-by-byte (t=0..3).
-- The MixColumns transformation output per column:
--   b0 = {02}*x0 ^ {03}*x1 ^      x2 ^      x3
--   b1 =      x0 ^ {02}*x1 ^ {03}*x2 ^      x3
--   b2 =      x0 ^      x1 ^ {02}*x2 ^ {03}*x3
--   b3 = {03}*x0 ^      x1 ^      x2 ^ {02}*x3
--
-- Because the matrix is circulant, only xtime() and xtimes3() are needed.
-- Four registers R0..R3 accumulate partial results over 4 cycles.
-- 'en' is asserted during t=0 (first byte) to clear the accumulators.
-- A 2-bit internal counter tracks which coefficient set to apply.
-- d0_out..d3_out are valid after the 4th clock (t=3).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mixcolumns_multiplier is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        en     : in  std_logic;  -- Pulse high on first byte of a new column
        d_in   : in  std_logic_vector(7 downto 0);
        d0_out : out std_logic_vector(7 downto 0);  -- b0 ready after t=3
        d1_out : out std_logic_vector(7 downto 0);  -- b1 ready after t=3
        d2_out : out std_logic_vector(7 downto 0);  -- b2 ready after t=3
        d3_out : out std_logic_vector(7 downto 0)   -- b3 ready after t=3
    );
end entity mixcolumns_multiplier;

architecture rtl of mixcolumns_multiplier is

    -- -------------------------------------------------------------------------
    -- GF(2^8) field operations (AES irreducible polynomial x^8+x^4+x^3+x+1)
    -- -------------------------------------------------------------------------

    -- Multiply by {02}: shift left 1, XOR with 0x1B if bit 7 was set
    function xtime(a : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        r := a(6 downto 0) & '0';
        if a(7) = '1' then
            r := r xor x"1B";
        end if;
        return r;
    end function;

    -- Multiply by {03} = {02} XOR {01}
    function times3(a : std_logic_vector(7 downto 0))
        return std_logic_vector is
    begin
        return xtime(a) xor a;
    end function;

    -- -------------------------------------------------------------------------
    -- Accumulator registers (Figure 4a: four D flip-flops per output)
    -- -------------------------------------------------------------------------
    signal R0, R1, R2, R3 : std_logic_vector(7 downto 0) := (others => '0');

    -- Masked values: cleared to 0 when 'en' is high (start of a new column)
    signal R0_m, R1_m, R2_m, R3_m : std_logic_vector(7 downto 0);

    -- 2-bit counter tracking the byte position within a column (t = 0..3)
    signal t : unsigned(1 downto 0) := (others => '0');

    -- Precomputed multiples of current input byte
    signal d_x2 : std_logic_vector(7 downto 0);
    signal d_x3 : std_logic_vector(7 downto 0);

begin

    -- Combinational multiples
    d_x2 <= xtime(d_in);
    d_x3 <= times3(d_in);

    -- Clear registers at first byte of each column
    R0_m <= (others => '0') when en = '1' else R0;
    R1_m <= (others => '0') when en = '1' else R1;
    R2_m <= (others => '0') when en = '1' else R2;
    R3_m <= (others => '0') when en = '1' else R3;

    -- -------------------------------------------------------------------------
    -- Accumulation logic
    --
    -- From Figure 4(b), the coefficient applied to byte xi for each output row:
    --
    --   t  byte  R0      R1      R2      R3
    --   0   x0   {02}    {01}    {01}    {03}
    --   1   x1   {03}    {02}    {01}    {01}
    --   2   x2   {01}    {03}    {02}    {01}
    --   3   x3   {01}    {01}    {03}    {02}
    --
    -- This is exactly the circulant MixColumns matrix read column-by-column.
    -- A 2-bit counter selects which coefficient set applies each cycle.
    -- -------------------------------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                R0 <= (others => '0');
                R1 <= (others => '0');
                R2 <= (others => '0');
                R3 <= (others => '0');
                t  <= (others => '0');
            else
                -- Advance byte-position counter
                if en = '1' then
                    t <= "01";   -- Next cycle will be t=1
                    R0 <= (others => '0');
                    R1 <= (others => '0');
                    R2 <= (others => '0');
                    R3 <= (others => '0');
                else
                    t <= t + 1;
                end if;

                -- Accumulate with the correct coefficient for this byte position
                case t is
                    when "00" =>   -- x0: coefficients {02},{01},{01},{03}
                        R0 <= R0_m xor d_x2;
                        R1 <= R1_m xor d_in;
                        R2 <= R2_m xor d_in;
                        R3 <= R3_m xor d_x3;

                    when "01" =>   -- x1: coefficients {03},{02},{01},{01}
                        R0 <= R0_m xor d_x3;
                        R1 <= R1_m xor d_x2;
                        R2 <= R2_m xor d_in;
                        R3 <= R3_m xor d_in;

                    when "10" =>   -- x2: coefficients {01},{03},{02},{01}
                        R0 <= R0_m xor d_in;
                        R1 <= R1_m xor d_x3;
                        R2 <= R2_m xor d_x2;
                        R3 <= R3_m xor d_in;

                    when others => -- x3: coefficients {01},{01},{03},{02}
                        R0 <= R0_m xor d_in;
                        R1 <= R1_m xor d_in;
                        R2 <= R2_m xor d_x3;
                        R3 <= R3_m xor d_x2;
                end case;
            end if;
        end if;
    end process;

    -- Outputs are valid after t=3 (4 cycles after 'en')
    d0_out <= R0;
    d1_out <= R1;
    d2_out <= R2;
    d3_out <= R3;

end architecture rtl;