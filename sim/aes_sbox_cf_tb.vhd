library ieee;
use ieee.std_logic_1164.all;

library std;
use std.env.all;

-- Directed testbench for the composite-field AES S-box.
-- Verifies a small set of well-known forward and inverse substitutions.
entity aes_sbox_cf_tb is
end entity aes_sbox_cf_tb;

architecture sim of aes_sbox_cf_tb is
    signal byte_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal usage    : std_logic := '0';
    signal byte_out : std_logic_vector(7 downto 0);
begin

    dut : entity work.aes_sbox_cf
        port map (
            byte_in  => byte_in,
            usage    => usage,
            byte_out => byte_out
        );

    stim : process
    begin
        -- Forward S-box spot checks.
        usage <= '0';

        byte_in <= x"00"; wait for 1 ns; assert byte_out = x"63" report "S-box 00 failed" severity failure;
        byte_in <= x"01"; wait for 1 ns; assert byte_out = x"7C" report "S-box 01 failed" severity failure;
        byte_in <= x"53"; wait for 1 ns; assert byte_out = x"ED" report "S-box 53 failed" severity failure;
        byte_in <= x"7C"; wait for 1 ns; assert byte_out = x"10" report "S-box 7C failed" severity failure;
        byte_in <= x"AE"; wait for 1 ns; assert byte_out = x"E4" report "S-box AE failed" severity failure;
        byte_in <= x"FF"; wait for 1 ns; assert byte_out = x"16" report "S-box FF failed" severity failure;

        -- Inverse S-box checks using the corresponding substituted values.
        usage <= '1';

        byte_in <= x"63"; wait for 1 ns; assert byte_out = x"00" report "InvS-box 63 failed" severity failure;
        byte_in <= x"7C"; wait for 1 ns; assert byte_out = x"01" report "InvS-box 7C failed" severity failure;
        byte_in <= x"ED"; wait for 1 ns; assert byte_out = x"53" report "InvS-box ED failed" severity failure;
        byte_in <= x"10"; wait for 1 ns; assert byte_out = x"7C" report "InvS-box 10 failed" severity failure;
        byte_in <= x"E4"; wait for 1 ns; assert byte_out = x"AE" report "InvS-box E4 failed" severity failure;
        byte_in <= x"16"; wait for 1 ns; assert byte_out = x"FF" report "InvS-box 16 failed" severity failure;

        report "aes_sbox_cf_tb PASSED" severity note;
        finish;
    end process;

end architecture sim;
