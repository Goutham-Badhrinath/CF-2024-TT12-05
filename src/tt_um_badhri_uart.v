`timescale 1ns / 1ps
/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_badhri_uart (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire   ena,
    input  wire   clk,
    input  wire   rst_n
);

    // IOs
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire uart_rx = ui_in[1];  // properly connect to input bit
    wire uart_tx;

    // LEDs and state
    reg [3:0] LED1, LED2, LED3, LED4;
    reg [7:0] LED;
    reg [3:0] i = 0;

    reg [31:0] instr_mem [0:15];
    reg [3:0] instr_idx = 0;
    reg [7:0] din = 0;
    reg wr_en = 0;
    reg rdy_clr = 0;

    wire [7:0] dout;
    wire rdy;
    wire tx_busy;

    // UART instantiation
    uart my_uart (
        .din(din),
        .wr_en(wr_en),
        .clk_50m(clk),
        .rst(rst_n),
        .tx(uart_tx),
        .tx_busy(tx_busy),
        .rx(uart_rx),
        .rdy(rdy),
        .rdy_clr(rdy_clr),
        .dout(dout)
    );

    // LED output through uo_out
    assign uo_out[0] = uart_tx;
    assign uo_out[4:1] = LED3;   // nibble output
    assign uo_out[7:5] = 3'b0;

    // Task converted to functionally equivalent block — task `=` used
    task automatic assign_nibble;
        input [3:0] nib;
        begin
            case (i)
                4'd0: begin instr_mem[instr_idx][31:28] = nib; LED1 <= nib; end
                4'd1: instr_mem[instr_idx][27:24] = nib;
                4'd2: begin instr_mem[instr_idx][23:20] = nib; LED2 <= nib; end
                4'd3: instr_mem[instr_idx][19:16] = nib;
                4'd4: begin instr_mem[instr_idx][15:12] = nib; LED3 <= nib; end
                4'd5: instr_mem[instr_idx][11:8]  = nib;
                4'd6: begin instr_mem[instr_idx][7:4]   = nib; LED4 <= nib; end
                4'd7: instr_mem[instr_idx][3:0]   = nib;
            endcase
        end
    endtask
    reg k = 0;
    // UART handling + instruction memory nibble accumulation
    always @(posedge clk) begin
        rdy_clr <= 0;
        wr_en <= 0;

        if (!rst_n) begin
            LED1 <= 0;
            LED2 <= 0;
            LED3 <= 0;
            LED4 <= 0;
            LED  <= 0;
            i <= 0;
            k <= 0;
            instr_idx <= 0;
        end else if (rdy && !tx_busy) begin
            case (dout)
                8'h30: assign_nibble(4'h0);
                8'h31: assign_nibble(4'h1);
                8'h32: assign_nibble(4'h2);
                8'h33: assign_nibble(4'h3);
                8'h34: assign_nibble(4'h4);
                8'h35: assign_nibble(4'h5);
                8'h36: assign_nibble(4'h6);
                8'h37: assign_nibble(4'h7);
                8'h38: assign_nibble(4'h8);
                8'h39: assign_nibble(4'h9);
                8'h41: assign_nibble(4'hA);
                8'h42: assign_nibble(4'hB);
                8'h43: assign_nibble(4'hC);
                8'h44: assign_nibble(4'hD);
                8'h45: assign_nibble(4'hE);
                8'h46: assign_nibble(4'hF);
            endcase

            if (i == 7 && k == 1) begin
                i <= 0;
                k <= 0; 
                if (instr_idx < 15)   // don’t overflow array
                instr_idx <= instr_idx + 1; end
            if(i < 7 && k == 1) begin
                k <= 0;
                i <= i + 1; end
            if(k < 1)
              k <= 1;

            LED <= dout;       // show received byte
            din <= dout;       // echo byte
            wr_en <= 1;
            rdy_clr <= 1;
        end
    end
    // Prevent unused warnings (like in example)
    wire _unused = &{ena, ui_in[0], ui_in[7:2], uio_in};

endmodule
