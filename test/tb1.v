// SPDX-FileCopyrightText: © 2024 Tiny Tapeout
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns/1ps

module tb1;

    // Clock & reset
    reg clk;
    reg rst_n;

    // TinyTapeout standard signals
    reg ena;
    reg  [7:0] ui_in;
    reg  [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // DUT instantiation
    tt_um_badhri_uart dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .ena    (ena),
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe)
    );

    // Clock generator (not really used by Cocotb, but useful for fallback sims)
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz sim clock

endmodule
