`timescale 1ns / 1ps
module CPU_Core(
    input clk,
    input uart_done_reg,
    output reg halt_flag
);

  // ───── Internal State ─────
  reg [31:0] PC;
  reg [31:0] instr_mem[0:63];   // Instruction memory
  reg [31:0] data_mem[0:63];    // Data memory
  reg [31:0] regfile[0:31];     // 32 general-purpose registers

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

  // ───── Register Initialization ─────
  integer i;
  initial begin
    PC = 0;
    halt_flag = 0;
    for (i = 0; i < 32; i = i + 1) regfile[i] = 0;
  end

  // ───── IF Stage ─────
  always @(posedge clk) begin
    if (!uart_done_reg || halt_flag)
      PC <= 0;
    else if (!stall) begin
      IF_ID_IR <= instr_mem[PC >> 2];
      IF_ID_PC <= PC;
      PC <= PC + 4;
    end
  end

  // ───── ID Stage ─────
  always @(posedge clk) begin
    if (uart_done_reg && !halt_flag) begin
      if (!stall) begin
        ID_EX_IR <= IF_ID_IR;
        ID_EX_PC <= IF_ID_PC;
        ID_EX_A <= regfile[IF_ID_IR[19:15]];
        ID_EX_B <= regfile[IF_ID_IR[24:20]];
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
  end

  // ───── EX Stage ─────
  always @(posedge clk) begin
    if (uart_done_reg && !halt_flag) begin
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
        7'b0000011, 7'b0100011: EX_MEM_ALUOut <= ID_EX_A + ID_EX_Imm; // load/store addr

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
  end

  // ───── MEM Stage ─────
  always @(posedge clk) begin
    if (uart_done_reg && !halt_flag) begin
      MEM_WB_IR <= EX_MEM_IR;
      MEM_WB_rd <= EX_MEM_rd;
      MEM_WB_ALUOut <= EX_MEM_ALUOut;

      if (EX_MEM_IR[6:0] == 7'b0000011) // lw
        MEM_WB_LMD <= data_mem[EX_MEM_ALUOut >> 2];
      else if (EX_MEM_IR[6:0] == 7'b0100011) // sw
        data_mem[EX_MEM_ALUOut >> 2] <= EX_MEM_B;
    end
  end

  // ───── WB Stage ─────
  always @(posedge clk) begin
    if (uart_done_reg && !halt_flag) begin
      case (MEM_WB_IR[6:0])
        7'b0110011, 7'b0010011, 7'b1101111:
          regfile[MEM_WB_rd] <= MEM_WB_ALUOut;
        7'b0000011:
          regfile[MEM_WB_rd] <= MEM_WB_LMD;
        7'b1110011:
          halt_flag <= 1; // ebreak
      endcase
    end
  end

  // ───── Hazard Detection ─────
  always @(*) begin
    if ((ID_EX_IR[6:0] == 7'b0000011) &&
        (ID_EX_rd != 0) &&
        ((ID_EX_rd == IF_ID_IR[19:15]) || (ID_EX_rd == IF_ID_IR[24:20])))
      stall = 1;
    else
      stall = 0;
  end

endmodule
