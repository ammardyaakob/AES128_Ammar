//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.03.2026 14:08:49
// Design Name: 
// Module Name: tb_aes128_encrypt
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`default_nettype none
// -----------------------------------------------------------------------------
// Testbench: tb_aes128_encrypt
//
// Self-checking testbench for aes128_encrypt wrapper.
//
// FIPS-197 Appendix B test vector:
//   Plaintext  : 3243F6A8 885A308D 313198A2 E0370734
//   Key        : 2B7E1516 28AED2A6 ABF71588 09CF4F3C
//   Ciphertext : 3925841D 02DC09FB DC118597 196A0B32
// -----------------------------------------------------------------------------
module tb_aes128_encrypt;

    localparam CLK_PERIOD = 10;  // 10 ns -> 100 MHz

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg         clk     = 0;
    reg         rst     = 1;
    reg         start   = 0;
    reg  [127:0] key    = 128'h2B7E151628AED2A6ABF7158809CF4F3C;
    reg  [127:0] block_in = 128'h3243F6A8885A308D313198A2E0370734;
    wire         done;
    wire [127:0] block_out;

    // -------------------------------------------------------------------------
    // Expected ciphertext
    // -------------------------------------------------------------------------
    localparam [127:0] EXPECTED = 128'h3925841D02DC09FBDC118597196A0B32;

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    aes128_encrypt u_dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .key      (key),
        .block_in (block_in),
        .done     (done),
        .block_out(block_out)
    );

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    integer timeout;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_aes128_encrypt);

        // 1. Reset for 2 cycles
        rst   = 1;
        start = 0;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);

        // 2. Pulse start for one cycle
        $display("INFO: Asserting start.");
        start = 1;
        @(posedge clk); 
        start = 0;

        // 3. Wait for done with timeout
        $display("INFO: Waiting for done...");
        timeout = 0;
        while (!done && timeout < 5000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        // 4. Check result
        if (timeout >= 5000) begin
            $display("FAIL: Timeout waiting for done.");
        end else if (block_out === EXPECTED) begin
            $display("PASS: block_out = %h (correct)", block_out);
        end else begin
            $display("FAIL: block_out = %h", block_out);
            $display("      expected  = %h", EXPECTED);
        end

        #(CLK_PERIOD * 10);
        $finish;
    end

endmodule
`default_nettype wire