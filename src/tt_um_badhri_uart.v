`timescale 1ns / 1ps
/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_badhri_uart(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    assign ui_in[0] = 0;
    assign ui_in[7:2] = 0;
    assign uo_out[7:5] = 0;
    assign uio_in = 0;
    assign uio_out = 0;
    assign uio_oe = 0;
    reg uart_rx = 0;
    wire uart_tx = 0;
    reg [3:0] LED3;
    always @(*) begin
        uart_rx = ui_in[1];
        
    end
    assign uo_out[0] = uart_tx;
    assign uo_out[4:1] = LED3;
    reg [7:0] LED;
    reg [3:0] LED1,LED2,LED4;
    reg [31:0] instr_mem;
    wire [7:0] dout;
    wire rdy;
    reg rdy_clr = 0;

    reg [7:0] din = 0;
    reg wr_en = 0;
    wire tx_busy;

    // Instantiate UART
    uart my_uart(
        .din(din),
        .wr_en(wr_en),
        .clk_50m(clk),     // Basys3 clock is 100MHz, but your UART expects 50MHz.
        .rst(rst_n),                   // This works *only* if your baud_gen assumes 100MHz,
                           // otherwise use a clock divider.
        .tx(uart_tx),
        .tx_busy(tx_busy),
        .rx(uart_rx),
        .rdy(rdy),
        .rdy_clr(rdy_clr),
        .dout(dout)
    );
    reg [3:0] i = 0;
    reg i1,i2,i3,i4;
    reg [3:0] start = 0;
    reg [3:0] endi = 0;
    
    task assign_nibble;
    input [3:0] nib;
    begin
        case (i)
            4'd0: begin instr_mem[31:28] <= nib; LED1 <= nib ; end
            4'd1: instr_mem[27:24] <= nib;  
            4'd2: begin instr_mem[23:20] <= nib; LED2 <= nib ; end
            4'd3: instr_mem[19:16] <= nib;
            4'd4: begin instr_mem[15:12] <= nib; LED3 <= nib ; end
            4'd5: instr_mem[11:8]  <= nib;
            4'd6: begin instr_mem[7:4]   <= nib; LED4 <= nib ; end
            4'd7: instr_mem[3:0]   <= nib;
        endcase
        
    end
    endtask

    // UART echo logic with LED output
    always @(posedge clk) begin
        // Clear rdy after reading
        rdy_clr <= 0;
        wr_en <= 0;
        if (rdy && !tx_busy) begin
            case(dout)
            8'h30: assign_nibble(4'h0); // '0'
            8'h31: assign_nibble(4'h1); // '1'
            8'h32: assign_nibble(4'h2); // '2'
            8'h33: assign_nibble(4'h3); // '3'
            8'h34: assign_nibble(4'h4); // '4'
            8'h35: assign_nibble(4'h5); // '5'
            8'h36: assign_nibble(4'h6); // '6'
            8'h37: assign_nibble(4'h7); // '7'
            8'h38: assign_nibble(4'h8); // '8'
            8'h39: assign_nibble(4'h9); // '9'
            8'h41: assign_nibble(4'hA); // 'A'
            8'h42: assign_nibble(4'hB); // 'B'
            8'h43: assign_nibble(4'hC); // 'C'
            8'h44: assign_nibble(4'hD); // 'D'
            8'h45: assign_nibble(4'hE); // 'E'
            8'h46: assign_nibble(4'hF); // 'F'
            endcase
            if(i == 7)
                i <= 0; 
            else
                i <= i + 1;
            LED <= dout;         // Show received byte on LEDs
            din <= dout;         // Echo the received byte back
            wr_en <= 1;          // Trigger transmission
            rdy_clr <= 1;        // Clear the rdy flag
        end
    end
    always @(negedge rst_n) begin
        if(!rst_n) begin
            LED3 <= 4'd0;
            LED1 <= 4'd0;
            LED2 <= 4'd0;
            LED4 <= 4'd0;
            i <= 0;
        end
    end

endmodule

