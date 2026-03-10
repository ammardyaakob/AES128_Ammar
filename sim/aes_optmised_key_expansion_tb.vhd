library ieee;
use ieee.std_logic_1164.all;

library std;
use std.env.all;

-- Directed testbench for the serial AES-128 key expansion block.
-- It checks both forward encryption order and reverse decryption order against
-- the standard FIPS-197 round-key sequence.
entity aes_key_expansion_tb is
end entity aes_key_expansion_tb;

architecture sim of aes_key_expansion_tb is
    constant CLK_PERIOD : time := 10 ns;

    type rk_array_t is array (0 to 10) of std_logic_vector(127 downto 0);

    -- Forward round-key sequence for key 00010203...0F.
    constant EXPECTED_ENC_RKS : rk_array_t := (
        x"000102030405060708090A0B0C0D0E0F",
        x"D6AA74FDD2AF72FADAA678F1D6AB76FE",
        x"B692CF0B643DBDF1BE9BC5006830B3FE",
        x"B6FF744ED2C2C9BF6C590CBF0469BF41",
        x"47F7F7BC95353E03F96C32BCFD058DFD",
        x"3CAAA3E8A99F9DEB50F3AF57ADF622AA",
        x"5E390F7DF7A69296A7553DC10AA31F6B",
        x"14F9701AE35FE28C440ADF4D4EA9C026",
        x"47438735A41C65B9E016BAF4AEBF7AD2",
        x"549932D1F08557681093ED9CBE2C974E",
        x"13111D7FE3944A17F307A78B4D2B30C5"
    );

    -- Reverse-order sequence expected when decrypt mode is requested.
    constant EXPECTED_DEC_RKS : rk_array_t := (
        x"13111D7FE3944A17F307A78B4D2B30C5",
        x"549932D1F08557681093ED9CBE2C974E",
        x"47438735A41C65B9E016BAF4AEBF7AD2",
        x"14F9701AE35FE28C440ADF4D4EA9C026",
        x"5E390F7DF7A69296A7553DC10AA31F6B",
        x"3CAAA3E8A99F9DEB50F3AF57ADF622AA",
        x"47F7F7BC95353E03F96C32BCFD058DFD",
        x"B6FF744ED2C2C9BF6C590CBF0469BF41",
        x"B692CF0B643DBDF1BE9BC5006830B3FE",
        x"D6AA74FDD2AF72FADAA678F1D6AB76FE",
        x"000102030405060708090A0B0C0D0E0F"
    );

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '0';
    signal start : std_logic := '0';
    signal encrypt : std_logic := '1';
    signal key_in : std_logic_vector(127 downto 0) := x"000102030405060708090A0B0C0D0E0F";

    signal roundkey_byte_out   : std_logic_vector(7 downto 0);
    signal roundkey_valid      : std_logic;
    signal round_idx_out       : std_logic_vector(3 downto 0);
    signal byte_idx_out        : std_logic_vector(3 downto 0);
    signal roundkey_block_out   : std_logic_vector(127 downto 0);
    signal roundkey_block_valid : std_logic;
    signal last_roundkey_out : std_logic_vector(127 downto 0);
    signal busy : std_logic;
    signal done : std_logic;
begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.aes_key_expansion
        generic map (
            support_decrypt => true
        )
        port map (
            clk                  => clk,
            rst                  => rst,
            start                => start,
            encrypt              => encrypt,
            key_in               => key_in,
            roundkey_byte_out    => roundkey_byte_out,
            roundkey_valid       => roundkey_valid,
            round_idx_out        => round_idx_out,
            byte_idx_out         => byte_idx_out,
            roundkey_block_out   => roundkey_block_out,
            roundkey_block_valid => roundkey_block_valid,
            last_roundkey_out    => last_roundkey_out,
            busy                 => busy,
            done                 => done
        );

    stim : process
        procedure run_case(
            constant enc_mode : std_logic;
            constant expected : rk_array_t;
            constant case_name : string
        ) is
            variable captured     : std_logic_vector(127 downto 0) := (others => '0');
            variable round_idx    : integer := 0;
            variable byte_idx     : integer := 0;
            variable stream_count : integer := 0;
            variable cycles       : integer := 0;
        begin
            -- Reset between runs so the start edge detector and internal state
            -- both restart from a known condition.
            encrypt <= enc_mode;
            rst <= '1';
            start <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            rst <= '0';
            wait until rising_edge(clk);

            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Capture the serial byte stream into 128-bit round-key blocks.
            while done /= '1' loop
                wait until rising_edge(clk);
                cycles := cycles + 1;

                assert cycles < 500
                    report case_name & " timed out waiting for done"
                    severity failure;

                if roundkey_valid = '1' then
                    captured(127 - byte_idx*8 downto 120 - byte_idx*8) := roundkey_byte_out;
                    stream_count := stream_count + 1;

                    if byte_idx = 15 then
                        assert captured = expected(round_idx)
                            report case_name & " round " & integer'image(round_idx) & " mismatch"
                            severity failure;

                        captured := (others => '0');
                        byte_idx := 0;
                        round_idx := round_idx + 1;
                    else
                        byte_idx := byte_idx + 1;
                    end if;
                end if;
            end loop;

            wait until rising_edge(clk);

            assert stream_count = 176
                report case_name & " streamed " & integer'image(stream_count) & " bytes instead of 176"
                severity failure;

            assert round_idx = 11
                report case_name & " produced " & integer'image(round_idx) & " round keys instead of 11"
                severity failure;

            assert busy = '0'
                report case_name & " left busy high after completion"
                severity failure;
        end procedure;
    begin
        -- Verify both supported stream directions.
        run_case('1', EXPECTED_ENC_RKS, "Encrypt key schedule");
        run_case('0', EXPECTED_DEC_RKS, "Decrypt key schedule");

        report "aes_key_expansion_tb PASSED" severity note;
        finish;
    end process;

end architecture sim;
