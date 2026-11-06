`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/29 14:59:27
// Design Name: 
// Module Name: DECODER
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

`define ADD     5'b00000    
`define SUB     5'b00010   
`define SLT     5'b00100
`define SLTU    5'b00101
`define AND     5'b01001
`define OR      5'b01010
`define XOR     5'b01011
`define SLL     5'b01110   
`define SRL     5'b01111    
`define SRA     5'b10000  
`define SRC0    5'b10001
`define SRC1    5'b10010

// M扩展操作码
`define MUL     5'b10011
`define MUL     5'b10011
`define MULH    5'b10100
`define MULHSU  5'b10101
`define MULHU   5'b10110
`define DIV     5'b10111
`define DIVU    5'b11000
`define REM     5'b11001
`define REMU    5'b11010
`define CRC16   5'b11100
`define MATRIX_CFG 5'b11101
`define MATRIX_RUN 5'b11110

module DECODER (
    input       [31:0]  inst,

    output  reg [4:0]   alu_op,
    output      [3:0]   dmem_access,
    output  reg [31:0]  imm,

    output      [4:0]   rf_ra0,
    output      [4:0]   rf_ra1,
    output      [4:0]   rf_wa,
    output  reg         rf_we,
    output  reg [2:0]   rf_wd_sel,

    output              alu_src0_sel,
    output              alu_src1_sel,

    output      [3:0]   br_type,

    // ===== Step 3 ??????CSR / ECALL / MRET ??????? =====
    output      [11:0]  csr_addr,    // CSR ??????????? inst[31:20]
    output  reg         csr_we,      // CSR д????????? rs1==x0 ???磩
    output  reg [2:0]   csr_op,      // CSR ???????????
                                     //   3'b000 = ?? CSR ???
                                     //   3'b001 = CSRRW   3'b101 = CSRRWI
                                     //   3'b010 = CSRRS   3'b110 = CSRRSI
                                     //   3'b011 = CSRRC   3'b111 = CSRRCI
    output  reg         is_ecall,    // ??????? ECALL ???
    output  reg         is_mret      // ??????? MRET ???
);

    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

    assign rf_ra0 = inst[19:15];
    assign rf_ra1 = inst[24:20];
    assign rf_wa  = inst[11:7];

    // CSR ?????????? inst[31:20]?????? zicsr ?????
    assign csr_addr = inst[31:20];

    assign alu_src0_sel = (opcode == 7'b0010111)|(opcode==7'b1101111)|(opcode==7'b1100011); // auipc
    assign alu_src1_sel = (opcode != 7'b0110011) && (opcode != 7'b0001011); // ?? R-type

    reg [3:0] dmem_acc_r;
    reg [3:0] br_type_r;

    assign dmem_access = dmem_acc_r;
    assign br_type     = br_type_r;

    always @(*) begin
        alu_op      = `ADD;
        rf_we       = 1'b0;
        rf_wd_sel   = 3'b001;
        imm         = 32'b0;
        dmem_acc_r  = 4'b0000;
        br_type_r   = 4'b0000;

        // Step 3 ??????CSR/SYSTEM ????
        csr_we      = 1'b0;
        csr_op      = 3'b000;
        is_ecall    = 1'b0;
        is_mret     = 1'b0;

        case (opcode)
        /* custom-0: CRC16 and complete CoreMark matrix accelerator. */
        7'b0001011: begin
            if ((funct7 == 7'b0000000) && (funct3 == 3'b000)) begin
                rf_we  = 1'b1;
                alu_op = `CRC16;
            end else if ((funct7 == 7'b0000000) && (funct3 == 3'b001)) begin
                rf_we  = 1'b1;
                alu_op = `MATRIX_CFG;
            end else if ((funct7 == 7'b0000000) && (funct3 == 3'b010)) begin
                rf_we  = 1'b1;
                alu_op = `MATRIX_RUN;
            end
        end

        /* R-type */
        7'b0110011: begin
            rf_we = 1'b1;
            case ({funct7,funct3})
                {7'b0000000,3'b000}: alu_op = `ADD;
                {7'b0100000,3'b000}: alu_op = `SUB;
                {7'b0000000,3'b010}: alu_op = `SLT;
                {7'b0000000,3'b011}: alu_op = `SLTU;
                {7'b0000000,3'b111}: alu_op = `AND;
                {7'b0000000,3'b110}: alu_op = `OR;
                {7'b0000000,3'b100}: alu_op = `XOR;
                {7'b0000000,3'b001}: alu_op = `SLL;
                {7'b0000000,3'b101}: alu_op = `SRL;
                {7'b0100000,3'b101}: alu_op = `SRA;
                
                // ========= M扩展指令 (funct7=0000001) =========
                {7'b0000001,3'b000}: alu_op = `MUL;
                {7'b0000001,3'b001}: alu_op = `MULH;
                {7'b0000001,3'b010}: alu_op = `MULHSU;
                {7'b0000001,3'b011}: alu_op = `MULHU;
                {7'b0000001,3'b100}: alu_op = `DIV;
                {7'b0000001,3'b101}: alu_op = `DIVU;
                {7'b0000001,3'b110}: alu_op = `REM;
                {7'b0000001,3'b111}: alu_op = `REMU;
            endcase
        end

        /* I-type */
        7'b0010011: begin
            rf_we = 1'b1;
            imm = {{20{inst[31]}},inst[31:20]};
            case (funct3)
                3'b000: alu_op = `ADD;
                3'b010: alu_op = `SLT;
                3'b011: alu_op = `SLTU;
                3'b111: alu_op = `AND;
                3'b110: alu_op = `OR;
                3'b100: alu_op = `XOR;
                3'b001: begin alu_op = `SLL; imm = {27'b0,inst[24:20]}; end
                3'b101: begin
                    imm = {27'b0,inst[24:20]};
                    alu_op = funct7[5] ? `SRA : `SRL;
                end
            endcase
        end

        /* LOAD */
        7'b0000011: begin
            rf_we     = 1'b1;
            rf_wd_sel = 3'b010;
            imm = {{20{inst[31]}},inst[31:20]};
            case (funct3)
                3'b000: dmem_acc_r = 4'b0001;
                3'b001: dmem_acc_r = 4'b0010;
                3'b010: dmem_acc_r = 4'b0011;
                3'b100: dmem_acc_r = 4'b0100;
                3'b101: dmem_acc_r = 4'b0101;
            endcase
        end

        /* STORE */
        7'b0100011: begin
            imm = {{20{inst[31]}},inst[31:25],inst[11:7]};
            case (funct3)
                3'b000: dmem_acc_r = 4'b1000;
                3'b001: dmem_acc_r = 4'b1001;
                3'b010: dmem_acc_r = 4'b1010;
            endcase
        end

        /* ========= LUI ========= */
        7'b0110111: begin
            rf_we        = 1'b1;
            alu_op       = `SRC1;
            imm          = {inst[31:12],12'b0};
        end

        /* ========= AUIPC ========= */
        7'b0010111: begin
            rf_we        = 1'b1;
            alu_op       = `ADD;
            imm          = {inst[31:12],12'b0};
        end


        /* BRANCH */
        7'b1100011: begin
            imm = {{19{inst[31]}},inst[31],inst[7],inst[30:25],inst[11:8],1'b0};
            case (funct3)
                3'b000: br_type_r = 4'b0001;
                3'b001: br_type_r = 4'b0010;
                3'b100: br_type_r = 4'b0011;
                3'b101: br_type_r = 4'b0100;
                3'b110: br_type_r = 4'b0101;
                3'b111: br_type_r = 4'b0110;
            endcase
        end

        /* JAL */
        7'b1101111: begin
            rf_we     = 1'b1;
            rf_wd_sel = 3'b000;
            br_type_r = 4'b0111;
            imm = {{11{inst[31]}},inst[31],inst[19:12],inst[20],inst[30:21],1'b0};
        end

        /* JALR */
        7'b1100111: begin
            rf_we     = 1'b1;
            rf_wd_sel = 3'b000;
            br_type_r = 4'b1000;
            imm = {{20{inst[31]}},inst[31:20]};
        end

        /* ====================== SYSTEM (Step 3 ????) ====================== */
        // opcode=7'b1110011 ?????
        //   - funct3=000: ECALL / EBREAK / MRET???? inst[31:20] ?????
        //   - funct3=001/010/011: CSRRW/S/C
        //   - funct3=101/110/111: CSRRWI/SI/CI
        7'b1110011: begin
            case (funct3)
                // ----- ECALL / EBREAK / MRET -----
                3'b000: begin
                    case (inst[31:20])
                        12'h000: is_ecall = 1'b1;   // ECALL
                        12'h001: ;                  // EBREAK???????????????????
                        12'h302: is_mret  = 1'b1;   // MRET
                        default: ;
                    endcase
                end

                // ----- CSRRW -----
                3'b001: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = 1'b1;
                    csr_op    = 3'b001;
                end

                // ----- CSRRS -----
                3'b010: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = (inst[19:15] != 5'b0);   // rs1==x0 ???д
                    csr_op    = 3'b010;
                end

                // ----- CSRRC -----
                3'b011: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = (inst[19:15] != 5'b0);
                    csr_op    = 3'b011;
                end

                // ----- CSRRWI -----
                3'b101: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = 1'b1;
                    csr_op    = 3'b101;
                    imm       = {27'b0, inst[19:15]};   // 5 λ?????
                end

                // ----- CSRRSI -----
                3'b110: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = (inst[19:15] != 5'b0);
                    csr_op    = 3'b110;
                    imm       = {27'b0, inst[19:15]};
                end

                // ----- CSRRCI -----
                3'b111: begin
                    rf_we     = 1'b1;
                    rf_wd_sel = 3'b100;
                    csr_we    = (inst[19:15] != 5'b0);
                    csr_op    = 3'b111;
                    imm       = {27'b0, inst[19:15]};
                end
            endcase
        end

        endcase
    end
endmodule
