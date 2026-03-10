library ieee;
use ieee.std_logic_1164.all;

library std;
use std.env.all;

-- System-level testbench for the byte-serial AES top-level.
-- It runs known-answer tests for both encrypt and decrypt, checks the key-stream
-- handshake, verifies the 16-byte output window, and performs round-trip tests
-- to catch protocol issues that might still pass isolated KATs.
entity aes_top_tb is
end entity aes_top_tb;

architecture sim of aes_top_tb is
    constant CLK_PERIOD : time := 10 ns;
    constant MAX_CASE_CYCLES : integer := 6000;
    constant QUIET_CYCLES_AFTER_DONE : integer := 4;
    constant EXPECTED_RK_PULSES : integer := 176;
    constant EXPECTED_OUTPUT_BYTES : integer := 16;

    type byte_array16_t is array (0 to 15) of std_logic_vector(7 downto 0);

    -- Convert a packed 128-bit block into the byte-serial ordering used by the DUT.
    function unpack_block(
        constant block_value : std_logic_vector(127 downto 0)
    ) return byte_array16_t is
        variable result : byte_array16_t;
    begin
        for i in 0 to 15 loop
            result(i) := block_value(127 - i*8 downto 120 - i*8);
        end loop;
        return result;
    end function;

    -- Pack byte-array form back into a 128-bit vector for reporting.
    function pack_block(
        constant block_value : byte_array16_t
    ) return std_logic_vector is
        variable result : std_logic_vector(127 downto 0);
    begin
        for i in 0 to 15 loop
            result(127 - i*8 downto 120 - i*8) := block_value(i);
        end loop;
        return result;
    end function;

    -- Small formatting helpers used only in failure reports.
    function hex_char(
        constant nibble : std_logic_vector(3 downto 0)
    ) return character is
    begin
        case nibble is
            when "0000" => return '0';
            when "0001" => return '1';
            when "0010" => return '2';
            when "0011" => return '3';
            when "0100" => return '4';
            when "0101" => return '5';
            when "0110" => return '6';
            when "0111" => return '7';
            when "1000" => return '8';
            when "1001" => return '9';
            when "1010" => return 'A';
            when "1011" => return 'B';
            when "1100" => return 'C';
            when "1101" => return 'D';
            when "1110" => return 'E';
            when "1111" => return 'F';
            when others => return 'X';
        end case;
    end function;

    function slv_to_hex(
        constant value : std_logic_vector
    ) return string is
        constant HEX_LEN : integer := (value'length + 3) / 4;
        variable padded : std_logic_vector(HEX_LEN * 4 - 1 downto 0) := (others => '0');
        variable result : string(1 to HEX_LEN);
    begin
        padded(value'length - 1 downto 0) := value;
        for i in 0 to HEX_LEN - 1 loop
            result(i + 1) := hex_char(
                padded(HEX_LEN * 4 - 1 - i * 4 downto HEX_LEN * 4 - 4 - i * 4)
            );
        end loop;
        return result;
    end function;

    function mode_name(
        constant enc_mode : std_logic
    ) return string is
    begin
        if enc_mode = '1' then
            return "encrypt";
        else
            return "decrypt";
        end if;
    end function;

    -- Standard AES-128 known-answer vectors.
    constant KEY_FIPS_197 : std_logic_vector(127 downto 0) :=
        x"000102030405060708090A0B0C0D0E0F";
    constant PT_FIPS_197 : byte_array16_t := unpack_block(
        x"00112233445566778899AABBCCDDEEFF"
    );
    constant CT_FIPS_197 : byte_array16_t := unpack_block(
        x"69C4E0D86A7B0430D8CDB78070B4C55A"
    );

    constant KEY_ZERO : std_logic_vector(127 downto 0) :=
        x"00000000000000000000000000000000";
    constant PT_ZERO : byte_array16_t := unpack_block(
        x"00000000000000000000000000000000"
    );
    constant CT_ZERO : byte_array16_t := unpack_block(
        x"66E94BD4EF8A2C3B884CFA59CA342B2E"
    );

    constant KEY_SP800_38A : std_logic_vector(127 downto 0) :=
        x"2B7E151628AED2A6ABF7158809CF4F3C";
    constant PT_SP800_38A_1 : byte_array16_t := unpack_block(
        x"6BC1BEE22E409F96E93D7E117393172A"
    );
    constant CT_SP800_38A_1 : byte_array16_t := unpack_block(
        x"3AD77BB40D7A3660A89ECAF32466EF97"
    );
    constant PT_SP800_38A_2 : byte_array16_t := unpack_block(
        x"AE2D8A571E03AC9C9EB76FAC45AF8E51"
    );
    constant CT_SP800_38A_2 : byte_array16_t := unpack_block(
        x"F5D3D58503B9699DE785895A96FDBAAF"
    );
    constant PT_SP800_38A_3 : byte_array16_t := unpack_block(
        x"30C81C46A35CE411E5FBC1191A0A52EF"
    );
    constant CT_SP800_38A_3 : byte_array16_t := unpack_block(
        x"43B1CD7F598ECE23881B00E3ED030688"
    );
    constant PT_SP800_38A_4 : byte_array16_t := unpack_block(
        x"F69F2445DF4F9B17AD2B417BE66C3710"
    );
    constant CT_SP800_38A_4 : byte_array16_t := unpack_block(
        x"7B0C785E27E8AD3F8223207104725DD4"
    );

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal start    : std_logic := '0';
    signal encrypt  : std_logic := '1';
    signal byte_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal key      : std_logic_vector(127 downto 0) := KEY_FIPS_197;
    signal done     : std_logic;
    signal byte_out : std_logic_vector(7 downto 0);
    signal rk_valid : std_logic;
begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.aes_top
        port map (
            clk      => clk,
            rst      => rst,
            start    => start,
            encrypt  => encrypt,
            byte_in  => byte_in,
            key      => key,
            done     => done,
            byte_out => byte_out,
            rk_valid => rk_valid
        );

    stim : process
        variable total_ops : integer := 0;
        variable encrypt_ops : integer := 0;
        variable decrypt_ops : integer := 0;
        variable roundtrip_pairs : integer := 0;
        variable total_first_latency : integer := 0;
        variable total_last_latency : integer := 0;
        variable min_first_latency : integer := MAX_CASE_CYCLES;
        variable max_first_latency : integer := 0;
        variable min_last_latency : integer := MAX_CASE_CYCLES;
        variable max_last_latency : integer := 0;
        variable passing_ops : integer := 0;
        variable failing_ops : integer := 0;
        variable mismatched_bytes : integer := 0;
        variable trailing_output_cases : integer := 0;
        variable roundtrip_failed_pairs : integer := 0;

        -- Reset helper used between independent test cases.
        procedure reset_dut is
        begin
            rst <= '1';
            start <= '0';
            byte_in <= (others => '0');
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            rst <= '0';
            wait until rising_edge(clk);

            assert done = '0'
                report "done was high immediately after reset release"
                severity failure;

            assert rk_valid = '0'
                report "rk_valid was high immediately after reset release"
                severity failure;
        end procedure;

        -- Aggregate latency and operation-count statistics for the final summary.
        procedure accumulate_metrics(
            constant first_latency : integer;
            constant last_latency  : integer;
            constant enc_mode      : std_logic
        ) is
        begin
            total_ops := total_ops + 1;
            total_first_latency := total_first_latency + first_latency;
            total_last_latency := total_last_latency + last_latency;

            if enc_mode = '1' then
                encrypt_ops := encrypt_ops + 1;
            else
                decrypt_ops := decrypt_ops + 1;
            end if;

            if first_latency < min_first_latency then
                min_first_latency := first_latency;
            end if;
            if first_latency > max_first_latency then
                max_first_latency := first_latency;
            end if;
            if last_latency < min_last_latency then
                min_last_latency := last_latency;
            end if;
            if last_latency > max_last_latency then
                max_last_latency := last_latency;
            end if;
        end procedure;

        procedure run_case(
            constant enc_mode       : std_logic;
            constant case_key       : std_logic_vector(127 downto 0);
            constant input_block    : byte_array16_t;
            constant expected_block : byte_array16_t;
            constant case_name      : string;
            variable captured_block : out byte_array16_t;
            variable first_latency  : out integer;
            variable last_latency   : out integer
        ) is
            variable captured      : byte_array16_t := (others => (others => '0'));
            variable feed_idx      : integer := 1;
            variable out_idx       : integer := 0;
            variable cycles        : integer := 0;
            variable rk_pulses     : integer := 0;
            variable done_pulses   : integer := 0;
            variable done_windows  : integer := 0;
            variable prev_done     : std_logic := '0';
            variable first_done_at : integer := -1;
            variable last_done_at  : integer := -1;
            variable trailing_byte_after_done : boolean := false;
            variable case_mismatches : integer := 0;
            variable first_mismatch_idx : integer := -1;
            variable first_mismatch_got : std_logic_vector(7 downto 0) := (others => '0');
            variable first_mismatch_expected : std_logic_vector(7 downto 0) := (others => '0');
        begin
            -- Start a block operation by presenting byte 0 with a start pulse.
            key <= case_key;
            encrypt <= enc_mode;
            byte_in <= input_block(0);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Feed remaining bytes on rk_valid and capture result bytes whenever
            -- done marks the output window as valid.
            while out_idx < 16 loop
                wait until rising_edge(clk);
                cycles := cycles + 1;

                assert cycles < MAX_CASE_CYCLES
                    report case_name & " timed out after " &
                           integer'image(cycles) & " cycles"
                    severity failure;

                if rk_valid = '1' then
                    rk_pulses := rk_pulses + 1;
                    if feed_idx < 16 then
                        byte_in <= input_block(feed_idx);
                        feed_idx := feed_idx + 1;
                    else
                        byte_in <= (others => '0');
                    end if;
                end if;

                if done = '1' and prev_done = '0' then
                    done_windows := done_windows + 1;
                end if;

                if done = '1' then
                    if first_done_at = -1 then
                        first_done_at := cycles;
                    end if;
                    last_done_at := cycles;
                    captured(out_idx) := byte_out;
                    out_idx := out_idx + 1;
                    done_pulses := done_pulses + 1;
                elsif prev_done = '1' and out_idx = EXPECTED_OUTPUT_BYTES - 1 then
                    captured(out_idx) := byte_out;
                    out_idx := out_idx + 1;
                    trailing_byte_after_done := true;
                end if;

                prev_done := done;
            end loop;

            byte_in <= (others => '0');

            wait until rising_edge(clk);
            assert done = '0'
                report case_name & " kept done high beyond the 16-byte output window"
                severity failure;

            for quiet_cycle in 2 to QUIET_CYCLES_AFTER_DONE loop
                wait until rising_edge(clk);
                assert done = '0'
                    report case_name & " re-asserted done unexpectedly after completion"
                    severity failure;
            end loop;

            assert rk_pulses = EXPECTED_RK_PULSES
                report case_name & " observed " & integer'image(rk_pulses) &
                       " rk_valid pulses instead of " &
                       integer'image(EXPECTED_RK_PULSES)
                severity failure;

            assert done_pulses = EXPECTED_OUTPUT_BYTES or
                   (done_pulses = EXPECTED_OUTPUT_BYTES - 1 and trailing_byte_after_done)
                report case_name & " observed " & integer'image(done_pulses) &
                       " done pulses and could not reconstruct a full " &
                       integer'image(EXPECTED_OUTPUT_BYTES) & "-byte output block"
                severity failure;

            assert done_windows = 1
                report case_name & " produced " & integer'image(done_windows) &
                       " done windows instead of 1"
                severity failure;

            assert last_done_at = first_done_at + done_pulses - 1
                report case_name & " output window was not contiguous: first=" &
                       integer'image(first_done_at) & " last=" &
                       integer'image(last_done_at)
                severity failure;

            if trailing_byte_after_done then
                trailing_output_cases := trailing_output_cases + 1;
                report case_name &
                       " protocol warning: final output byte was only visible after done de-asserted"
                    severity warning;
            end if;

            for i in 0 to 15 loop
                if captured(i) /= expected_block(i) then
                    case_mismatches := case_mismatches + 1;
                    mismatched_bytes := mismatched_bytes + 1;
                    if first_mismatch_idx = -1 then
                        first_mismatch_idx := i;
                        first_mismatch_got := captured(i);
                        first_mismatch_expected := expected_block(i);
                    end if;
                end if;
            end loop;

            captured_block := captured;
            first_latency := first_done_at;
            last_latency := last_done_at;

            if case_mismatches = 0 then
                passing_ops := passing_ops + 1;
                report "PASS [" & mode_name(enc_mode) & "] " & case_name
                    severity note;
            else
                failing_ops := failing_ops + 1;
                report "FAIL [" & mode_name(enc_mode) & "] " & case_name &
                       " key=" & slv_to_hex(case_key) &
                       " input=" & slv_to_hex(pack_block(input_block)) &
                       " observed=" & slv_to_hex(pack_block(captured)) &
                       " expected=" & slv_to_hex(pack_block(expected_block)) &
                       " mismatches=" & integer'image(case_mismatches) &
                       " first_mismatch_byte=" & integer'image(first_mismatch_idx) &
                       " got=" & slv_to_hex(first_mismatch_got) &
                       " expected_byte=" & slv_to_hex(first_mismatch_expected) &
                       " trailing_byte_after_done=" &
                       boolean'image(trailing_byte_after_done)
                    severity warning;
            end if;
        end procedure;

        -- Run paired encrypt/decrypt known-answer tests using the same vector set.
        procedure run_known_answer_pair(
            constant case_name   : string;
            constant case_key    : std_logic_vector(127 downto 0);
            constant plain_block : byte_array16_t;
            constant cipher_block : byte_array16_t
        ) is
            variable captured : byte_array16_t;
            variable first_latency : integer;
            variable last_latency  : integer;
        begin
            reset_dut;
            run_case('1', case_key, plain_block, cipher_block,
                     case_name, captured, first_latency, last_latency);
            accumulate_metrics(first_latency, last_latency, '1');

            reset_dut;
            run_case('0', case_key, cipher_block, plain_block,
                     case_name, captured, first_latency, last_latency);
            accumulate_metrics(first_latency, last_latency, '0');
        end procedure;

        -- Check full encrypt->decrypt roundtrip behaviour as an integration test.
        procedure run_roundtrip_pair(
            constant case_name   : string;
            constant case_key    : std_logic_vector(127 downto 0);
            constant plain_block : byte_array16_t;
            constant cipher_block : byte_array16_t
        ) is
            variable enc_block : byte_array16_t;
            variable dec_block : byte_array16_t;
            variable first_latency : integer;
            variable last_latency  : integer;
        begin
            reset_dut;
            run_case('1', case_key, plain_block, cipher_block,
                     case_name & " roundtrip",
                     enc_block, first_latency, last_latency);
            accumulate_metrics(first_latency, last_latency, '1');

            reset_dut;
            run_case('0', case_key, enc_block, plain_block,
                     case_name & " roundtrip",
                     dec_block, first_latency, last_latency);
            accumulate_metrics(first_latency, last_latency, '0');

            if dec_block /= plain_block then
                roundtrip_failed_pairs := roundtrip_failed_pairs + 1;
                report case_name &
                       " roundtrip failure: decrypt(encrypt(plaintext)) /= plaintext"
                    severity warning;
            end if;

            roundtrip_pairs := roundtrip_pairs + 1;
        end procedure;
    begin
        -- Known-answer tests followed by end-to-end roundtrip checks.
        run_known_answer_pair("FIPS-197 example", KEY_FIPS_197, PT_FIPS_197, CT_FIPS_197);
        run_known_answer_pair("All-zero vector", KEY_ZERO, PT_ZERO, CT_ZERO);
        run_known_answer_pair("SP800-38A block 1", KEY_SP800_38A, PT_SP800_38A_1, CT_SP800_38A_1);
        run_known_answer_pair("SP800-38A block 2", KEY_SP800_38A, PT_SP800_38A_2, CT_SP800_38A_2);
        run_known_answer_pair("SP800-38A block 3", KEY_SP800_38A, PT_SP800_38A_3, CT_SP800_38A_3);
        run_known_answer_pair("SP800-38A block 4", KEY_SP800_38A, PT_SP800_38A_4, CT_SP800_38A_4);

        run_roundtrip_pair("FIPS-197", KEY_FIPS_197, PT_FIPS_197, CT_FIPS_197);
        run_roundtrip_pair("All-zero", KEY_ZERO, PT_ZERO, CT_ZERO);
        run_roundtrip_pair("SP800-38A block 4", KEY_SP800_38A, PT_SP800_38A_4, CT_SP800_38A_4);

        report "aes_top_tb SUMMARY total=" & integer'image(total_ops) &
               " pass=" & integer'image(passing_ops) &
               " fail=" & integer'image(failing_ops) &
               " encrypt=" & integer'image(encrypt_ops) &
               " decrypt=" & integer'image(decrypt_ops) &
               " roundtrip_pairs=" & integer'image(roundtrip_pairs)
            severity note;

        assert encrypt_ops > 0
            report "aes_top_tb did not execute any encrypt operations"
            severity failure;

        assert decrypt_ops > 0
            report "aes_top_tb did not execute any decrypt operations"
            severity failure;

        if failing_ops = 0 and roundtrip_failed_pairs = 0 and trailing_output_cases = 0 then
            report "aes_top_tb PASSED" severity note;
            finish;
        else
            assert false
                report "aes_top_tb FAILED quality gate: failing_ops=" &
                       integer'image(failing_ops) &
                       ", roundtrip_failed_pairs=" &
                       integer'image(roundtrip_failed_pairs) &
                       ", trailing_output_cases=" &
                       integer'image(trailing_output_cases)
                severity failure;
        end if;
    end process;

end architecture sim;
