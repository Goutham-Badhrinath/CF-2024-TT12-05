//`timescale 1ns / 1ps
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

    wire uart_rx = ui_in[1];  // properly connect to input bit
    wire start = ui_in[0]; // start CPU
    wire uart_tx;

    
    reg [3:0] i;

    reg [31:0] instr_mem [0:15];
    reg [3:0] instr_idx;
    reg [7:0] din = 0;
    reg wr_en;
    reg rdy_clr;

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


    // Task converted to functionally equivalent block — task `=` used
    task automatic assign_nibble;
        input [3:0] nib;
        begin
            case (i)
                4'd0: begin instr_mem[instr_idx][31:28] <= nib;  end
                4'd1: instr_mem[instr_idx][27:24] <= nib;
                4'd2: begin instr_mem[instr_idx][23:20] <= nib;  end
                4'd3: instr_mem[instr_idx][19:16] <= nib;
                4'd4: begin instr_mem[instr_idx][15:12] <= nib;  end
                4'd5: instr_mem[instr_idx][11:8]  <= nib;
                4'd6: begin instr_mem[instr_idx][7:4]   <= nib;  end
                4'd7: instr_mem[instr_idx][3:0]   <= nib;
                default : instr_mem[instr_idx] <= 0;
            endcase
        end
    endtask
    reg k;
    // UART handling + instruction memory nibble accumulation
    always @(posedge clk) begin
        rdy_clr <= 0;
        wr_en <= 0;

        if (!rst_n) begin
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

            din <= dout;       // echo byte
            wr_en <= 1;
            rdy_clr <= 1;
        end
    end

    //////////////////////////////////////////////////
                // Goutham CPU works here // 
                // Progress : Init Done, 
                // still if possible pipeline guards for gl_test
    //////////////////////////////////////////////////

    // ───── Internal State ─────
    reg [31:0] PC;
    reg [31:0] data_mem[0:3];    // Data memory
    reg [31:0] regfile[0:7];     // 32 general-purpose registers
    reg halt_flag;
    reg [7:0] x3;
    assign uio_oe = 8'b11111111; // enable all to outputs

    always @(posedge clk or posedge rst_n) begin
        if (!rst_n || !start) begin
        x3 <= 8'b00000000;
    end else begin
        x3 <= regfile[3][7:0];
    end
end

// Drive to output pins
    assign uio_out[7:0] = x3;
    assign uo_out[0]   = uart_tx;
    assign uo_out[7:1] = 7'b0000000;

  // ───── Pipeline Registers ─────
  reg [31:0] IF_ID_IR, IF_ID_PC;
  reg [31:0] ID_EX_IR, ID_EX_PC, ID_EX_A, ID_EX_B, ID_EX_Imm;
  reg [4:0]  ID_EX_rd;
  reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
  reg [4:0]  EX_MEM_rd;
  reg        EX_MEM_cond;
  reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;
  reg [4:0]  MEM_WB_rd;

  reg stall;

  // ───── IF Stage ─────
  always @(posedge clk) begin
    if (!start || halt_flag)
      PC <= 0;
    else if (!stall) begin
      IF_ID_IR <= instr_mem[PC >> 2];
      IF_ID_PC <= PC;
       if (EX_MEM_cond)  // branch taken
          PC <= EX_MEM_ALUOut;
      else
          PC <= PC + 4;
    end
    else if (!start) begin
        IF_ID_IR <= 0;
        IF_ID_PC <= 0;
        PC <= 0;
    end
  end

  // ───── ID Stage ─────
  always @(posedge clk) begin
    if (start && !halt_flag) begin
      if (!stall) begin
        ID_EX_IR <= IF_ID_IR;
        ID_EX_PC <= IF_ID_PC;
          ID_EX_A <= regfile[IF_ID_IR[17:15]];
          ID_EX_B <= regfile[IF_ID_IR[22:20]];
        ID_EX_rd <= IF_ID_IR[11:7];

        case (IF_ID_IR[6:0])
          7'b0010011, 7'b0000011:
            ID_EX_Imm <= {{20{IF_ID_IR[31]}}, IF_ID_IR[31:20]};
          7'b0100011:
            ID_EX_Imm <= {{20{IF_ID_IR[31]}}, IF_ID_IR[31:25], IF_ID_IR[11:7]};
          7'b1100011:
            ID_EX_Imm <= {{19{IF_ID_IR[31]}}, IF_ID_IR[31], IF_ID_IR[7],
                           IF_ID_IR[30:25], IF_ID_IR[11:8], 1'b0};
          7'b1101111:
            ID_EX_Imm <= {{11{IF_ID_IR[31]}}, IF_ID_IR[31], IF_ID_IR[19:12],
                           IF_ID_IR[20], IF_ID_IR[30:21], 1'b0};
          default: ID_EX_Imm <= 0;
        endcase
      end else begin
        ID_EX_IR <= 32'b0; // Insert NOP on stall
      end
    end
    else if (!start) begin
        ID_EX_IR <= 0;
        ID_EX_PC <= 0;
        ID_EX_A <= 0;
        ID_EX_B <= 0;
        ID_EX_rd <= 0;
        ID_EX_Imm <= 0;
    end
  end

  // ───── EX Stage ─────
  always @(posedge clk) begin
    if (start && !halt_flag) begin
      EX_MEM_IR <= ID_EX_IR;
      EX_MEM_B <= ID_EX_B;
      EX_MEM_rd <= ID_EX_rd;
      EX_MEM_cond <= 0;

      case (ID_EX_IR[6:0])
        7'b0110011: begin // R-type
          case ({ID_EX_IR[31:25], ID_EX_IR[14:12]})
            10'b0000000000: EX_MEM_ALUOut <= ID_EX_A + ID_EX_B; // add
            10'b0100000000: EX_MEM_ALUOut <= ID_EX_A - ID_EX_B; // sub
            10'b0000000111: EX_MEM_ALUOut <= ID_EX_A & ID_EX_B; // and
            10'b0000000110: EX_MEM_ALUOut <= ID_EX_A | ID_EX_B; // or
            10'b0000000010: EX_MEM_ALUOut <= (ID_EX_A < ID_EX_B) ? 1 : 0; // slt
            10'b0000000001: EX_MEM_ALUOut <= ID_EX_A << ID_EX_B[4:0]; // sll
            10'b0000000101: EX_MEM_ALUOut <= ID_EX_A >> ID_EX_B[4:0]; // srl
            10'b0000000100: EX_MEM_ALUOut <= ID_EX_A ^ ID_EX_B;       // xor
            default: EX_MEM_ALUOut <= 0;
          endcase
        end

        7'b0010011: begin // I-type ALU
          case (ID_EX_IR[14:12])
            3'b000: EX_MEM_ALUOut <= ID_EX_A + ID_EX_Imm; // addi
            3'b111: EX_MEM_ALUOut <= ID_EX_A & ID_EX_Imm; // andi
            3'b110: EX_MEM_ALUOut <= ID_EX_A | ID_EX_Imm; // ori
            default: EX_MEM_ALUOut <= 0;
          endcase
        end

        7'b1101111: EX_MEM_ALUOut <= ID_EX_PC + ID_EX_Imm; // jal
          7'b0000011, 7'b0100011: EX_MEM_ALUOut <= ((ID_EX_A + ID_EX_Imm)>>2); // load/store addr

        7'b1100011: begin // Branch
          case (ID_EX_IR[14:12])
            3'b000: if (ID_EX_A == ID_EX_B) begin EX_MEM_ALUOut <= ID_EX_PC + ID_EX_Imm; EX_MEM_cond <= 1; end
            3'b001: if (ID_EX_A != ID_EX_B) begin EX_MEM_ALUOut <= ID_EX_PC + ID_EX_Imm; EX_MEM_cond <= 1; end
            3'b100: if ($signed(ID_EX_A) < $signed(ID_EX_B)) begin EX_MEM_ALUOut <= ID_EX_PC + ID_EX_Imm; EX_MEM_cond <= 1; end
            default: ;
          endcase
        end

        default: EX_MEM_ALUOut <= 0;
      endcase
    end
    else if (!start) begin
        EX_MEM_IR <= 0;
        EX_MEM_B <= 0;
        EX_MEM_rd <= 0;
        EX_MEM_cond <= 0;
        EX_MEM_ALUOut <= 0;
    end
  end

  // ───── MEM Stage ─────
  always @(posedge clk) begin
    if (start && !halt_flag) begin
      MEM_WB_IR <= EX_MEM_IR;
      MEM_WB_rd <= EX_MEM_rd;
      MEM_WB_ALUOut <= EX_MEM_ALUOut;

      if (EX_MEM_IR[6:0] == 7'b0000011) // lw
          MEM_WB_LMD <= data_mem[EX_MEM_ALUOut[1:0]];
      else if (EX_MEM_IR[6:0] == 7'b0100011) // sw
          data_mem[EX_MEM_ALUOut[1:0]] <= EX_MEM_B;
    end
    else if (!start) begin
        MEM_WB_IR <= 0;
        MEM_WB_rd <= 0;
        MEM_WB_ALUOut <= 0;
        MEM_WB_LMD <= 0; 
        data_mem[0] <= 0;
        data_mem[1] <= 0;
        data_mem[2] <= 0;
        data_mem[3] <= 0;
    end
  end

  // ───── WB Stage ─────
  always @(posedge clk) begin
    if (start && !halt_flag) begin
      case (MEM_WB_IR[6:0])
        7'b0110011, 7'b0010011, 7'b1101111:
            regfile[MEM_WB_rd[2:0]] <= MEM_WB_ALUOut;
        7'b0000011:
            regfile[MEM_WB_rd[2:0]] <= MEM_WB_LMD;
        7'b1110011:
          halt_flag <= 1; // ebreak
      endcase
    end
    else if (!start) begin
        regfile[0] <= 0;
        regfile[1] <= 0;
        regfile[2] <= 0;
        regfile[3] <= 0;
        regfile[4] <= 0;
        regfile[5] <= 0;
        regfile[6] <= 0;
        regfile[7] <= 0;
        halt_flag <= 0;
    end
  end

  // ───── Hazard Detection ─────
    always @(posedge clk) begin
    if ((ID_EX_IR[6:0] == 7'b0000011) &&
        (ID_EX_rd != 0) &&
        ((ID_EX_rd == IF_ID_IR[19:15]) || (ID_EX_rd == IF_ID_IR[24:20])))
      stall <= 1;
    else
      stall <= 0;
  end




    // Prevent unused warnings (like in example)
    wire _unused = &{ena, ui_in[7:2], uio_in};

endmodule
