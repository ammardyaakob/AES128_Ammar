//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06.03.2026 14:06:19
// Design Name: 
// Module Name: aes128_encrypt
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
// AES-128 encryptor wrapper
//
// Wraps the VHDL aes_top entity which uses a serial byte-at-a-time interface.
// This wrapper:
//   1. Waits for aes_top's key expansion to complete (rk_valid rising edge)
//   2. Feeds the 16 plaintext bytes one per clock into byte_in
//   3. Collects 16 ciphertext bytes from byte_out when done is high
//   4. Asserts done for one cycle once block_out holds the ciphertext
//
// -----------------------------------------------------------------------------
module aes128_encrypt (
    input  wire         clk,
    input  wire         rst,        // synchronous, active high
    input  wire         start,      // 1-cycle pulse when IDLE
    input  wire [127:0] key,
    input  wire [127:0] block_in,
    output wire         done,       // 1-cycle pulse when block_out valid
    output reg  [127:0] block_out
);

    // -------------------------------------------------------------------------
    // Internal signals connecting to aes_top
    // -------------------------------------------------------------------------
    wire        rk_valid;
    wire        core_done;
    wire [7:0]  byte_out_core;
    reg  [4:0]  byte_sel;           // which byte index to drive onto byte_in
    wire [7:0]  byte_in_wire;      
    reg         start_reg;
    wire        encrypt_tie = 1'b1; // encryption only

    assign byte_in_wire = block_in[127 - byte_sel*8 -: 8];

    // -------------------------------------------------------------------------
    // FSM states
    // -------------------------------------------------------------------------
    localparam [2:0]
        IDLE        = 3'd0,
        WAIT_RK     = 3'd1,   // wait for key expansion (rk_valid)
        FEED_BYTES  = 3'd2,   // clock in 16 plaintext bytes
        COLLECT     = 3'd3,   // collect 16 ciphertext bytes
        DONE_ST     = 3'd4;   // assert done for one cycle

    reg [2:0]  state;

    // Byte counter
    reg [4:0]  byte_cnt;

    // Output shift register - collects bytes MSB-first
    reg [127:0] block_out_shift;

    assign done = (state == DONE_ST);

    // -------------------------------------------------------------------------
    // Instantiate the VHDL aes_top component
    // -------------------------------------------------------------------------
    aes_top u_aes_top (
        .clk      (clk),
        .rst      (rst),
        .start    (start_reg),
        .encrypt  (encrypt_tie),
        .byte_in  (byte_in_wire),
        .key      (key),
        .done     (core_done),
        .byte_out (byte_out_core),
        .rk_valid (rk_valid)
    );

    // -------------------------------------------------------------------------
    // FSM - sequential
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            byte_cnt        <= 5'd0;
            byte_sel        <= 5'd0;
            start_reg       <= 1'b0;
            block_out       <= 128'h0;
            block_out_shift <= 128'h0;
        end else begin

            case (state)
                // --------------------------------------------------------------
                IDLE: begin
                    byte_cnt  <= 5'd0;
                    byte_sel  <= 5'd0;   // pre-select byte 0 so it is ready
                    if (start) begin
                        start_reg <= 1'b1;
                        state     <= WAIT_RK;
                    end
                end

                // --------------------------------------------------------------
                WAIT_RK: begin
                    start_reg <= 1'b0;
                    if (rk_valid) begin
                        byte_sel  <= 5'd1;
                        byte_cnt  <= 5'd1;
                        state     <= FEED_BYTES;
                    end
                end

                // --------------------------------------------------------------
                FEED_BYTES: begin
                    if (byte_cnt < 5'd15) begin
                        byte_sel <= byte_sel + 1'b1;
                        byte_cnt <= byte_cnt + 1'b1;
                    end else begin
                        byte_sel  <= 5'd0;
                        byte_cnt  <= 5'd0;
                        state     <= COLLECT;
                    end
                end

                // --------------------------------------------------------------
                // Collect 16 output bytes
                // --------------------------------------------------------------
                COLLECT: begin
                    if (core_done) begin
                        if (byte_cnt == 5'd15) begin
                            // Last byte: complete the full 128-bit word now
                            block_out <= {block_out_shift[119:0], byte_out_core};
                            state     <= DONE_ST;
                        end else begin
                            block_out_shift <= {block_out_shift[119:0], byte_out_core};
                            byte_cnt        <= byte_cnt + 1'b1;
                        end
                    end
                end
                
                DONE_ST: begin
                    byte_cnt <= 5'd0;
                    state    <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
    
`ifndef SYNTHESIS
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, aes128_encrypt);
    end
`endif

endmodule
`default_nettype wire