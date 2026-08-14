module ControlUnit (
    input [6:0] opcode, funct7,
    input [2:0] funct3,
    output reg reg_write,
    output reg mem_write,
    output reg mem_read,
    output reg reg_write_src, //select from alu result and result of a mem read
    output reg alu_a_src, //select between current pc and reg file
    output reg alu_b_src, //feed alu operand b from sign extender or reg file
    output reg cond_br, //if there is a condition branch
    output reg jump, //set up for a jump (mux pc+4 with reg write bus)
    output reg word, //for alu
    output reg [2:0] sign_format,
    output reg [3:0] alu_op,
    output reg rs1_needed, //for hazards
    output reg rs2_needed, //for hazards
    output reg illegal_instruction,
    output reg halt
);

// match SignExtender.v
localparam I_TYPE = 3'd0, S_TYPE = 3'd1, B_TYPE = 3'd2,
           U_TYPE = 3'd3, J_TYPE = 3'd4;

// match ALU.v
localparam ALU_ADD = 4'd0, ALU_SUB = 4'd1, ALU_SLL = 4'd2,
           ALU_SLT = 4'd3, ALU_SLTU = 4'd4, ALU_XOR = 4'd5,
           ALU_SRL = 4'd6, ALU_SRA = 4'd7, ALU_OR  = 4'd8,
           ALU_AND = 4'd9, ALU_PASS_B = 4'd10;

always @(*) begin
    //set defaults
    reg_write = 0;
    mem_write = 0;
    mem_read = 0;
    reg_write_src = 0;
    alu_a_src = 0;
    alu_b_src = 0;
    cond_br = 0;
    jump = 0;
    word = 0;
    sign_format = I_TYPE;
    alu_op = ALU_ADD;
    rs1_needed = 1;
    rs2_needed = 1;
    illegal_instruction = 0;
    halt = 0;

    case (opcode)
        7'b011_0011: begin //R-type
            reg_write = 1;
            case (funct3)
                3'b000: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_ADD;
                        7'b010_0000: alu_op = ALU_SUB;
                        //7'b000_0001: MUL goes here later
                    endcase
                end
                3'b001: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SLL;
                    endcase
                end
                3'b010: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SLT;
                    endcase
                end
                3'b011: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SLTU;
                    endcase
                end
                3'b100: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_XOR;
                    endcase
                end
                3'b101: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SRL;
                        7'b010_0000: alu_op = ALU_SRA;
                    endcase
                end
                3'b110: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_OR;
                    endcase
                end
                3'b111: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_AND;
                    endcase
                end
            endcase
        end

        7'b011_1011: begin //R-type W (ADDW, SUBW, SLLW, SRLW, SRAW)
            reg_write = 1;
            word = 1;
            case (funct3)
                3'b000: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_ADD;
                        7'b010_0000: alu_op = ALU_SUB;
                        //7'b000_0001: MULW goes here later
                    endcase
                end
                3'b001: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SLL;
                    endcase
                end
                3'b101: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SRL;
                        7'b010_0000: alu_op = ALU_SRA;
                    endcase
                end
            endcase
        end

        7'b001_0011: begin //I-type ALU
            rs2_needed = 0;
            reg_write = 1;
            alu_b_src = 1;
            sign_format = I_TYPE;
            case (funct3)
                3'b000: alu_op = ALU_ADD;  //ADDI
                3'b010: alu_op = ALU_SLT;  //SLTI
                3'b011: alu_op = ALU_SLTU; //SLTIU
                3'b100: alu_op = ALU_XOR;  //XORI
                3'b110: alu_op = ALU_OR;   //ORI
                3'b111: alu_op = ALU_AND;  //ANDI
                //shifts: RV64I shamt is 6 bits, so funct7[0] is shamt[5],
                //not part of the function code. match funct7[6:1] only.
                3'b001: begin
                    case (funct7[6:1])
                        6'b000_000: alu_op = ALU_SLL; //SLLI
                    endcase
                end
                3'b101: begin
                    case (funct7[6:1])
                        6'b000_000: alu_op = ALU_SRL; //SRLI
                        6'b010_000: alu_op = ALU_SRA; //SRAI
                    endcase
                end
            endcase
        end

        7'b001_1011: begin //I-type W (ADDIW, SLLIW, SRLIW, SRAIW)
            rs2_needed = 0;
            reg_write = 1;
            alu_b_src = 1;
            word = 1;
            sign_format = I_TYPE;
            case (funct3)
                3'b000: alu_op = ALU_ADD; //ADDIW
                //W-shift shamt is 5 bits, so full funct7 is the function code
                3'b001: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SLL; //SLLIW
                    endcase
                end
                3'b101: begin
                    case (funct7)
                        7'b000_0000: alu_op = ALU_SRL; //SRLIW
                        7'b010_0000: alu_op = ALU_SRA; //SRAIW
                    endcase
                end
            endcase
        end

        7'b000_0011: begin //loads (LB LH LW LD LBU LHU LWU)
            rs2_needed =  0;
            reg_write = 1;
            mem_read = 1;
            reg_write_src = 1; //write bus from data memory
            alu_b_src = 1;     //address = rs1 + imm
            sign_format = I_TYPE;
            alu_op = ALU_ADD;
            //size/signedness handled by funct3 routed to DataMemory
        end

        7'b010_0011: begin //stores (SB SH SW SD)
            mem_write = 1;
            alu_b_src = 1;     //address = rs1 + imm
            sign_format = S_TYPE;
            alu_op = ALU_ADD;
        end

        7'b110_0011: begin //conditional branches (BEQ BNE BLT BGE BLTU BGEU)
            cond_br = 1;
            sign_format = B_TYPE;
            //comparison type handled by funct3 routed to Comparator
            // compute pc + imm
            alu_a_src = 1;
            alu_b_src = 1;
        end

        7'b110_1111: begin //JAL
            reg_write = 1; //pc+4 onto write bus, gated by jump
            jump = 1;      //next pc from alu result
            alu_a_src = 1; //operand a = pc
            alu_b_src = 1; //operand b = imm -> target = pc + imm
            sign_format = J_TYPE;
            alu_op = ALU_ADD;
            rs1_needed = 0;
            rs2_needed = 0;
        end

        7'b110_0111: begin //JALR
            reg_write = 1; //pc+4 onto write bus, gated by jump
            jump = 1;      //next pc from alu result (lsb cleared in datapath)
            alu_b_src = 1; //operand b = imm -> target = rs1 + imm
            sign_format = I_TYPE;
            alu_op = ALU_ADD;
            rs2_needed = 0;
        end

        7'b011_0111: begin //LUI
            reg_write = 1;
            alu_b_src = 1;
            sign_format = U_TYPE;
            alu_op = ALU_PASS_B;
            rs1_needed = 0;
            rs2_needed = 0;
        end

        7'b001_0111: begin //AUIPC
            reg_write = 1;
            alu_a_src = 1; //operand a = pc
            alu_b_src = 1; //operand b = imm
            sign_format = U_TYPE;
            alu_op = ALU_ADD;
            rs1_needed = 0;
            rs2_needed = 0;
        end
        7'b111_0011: begin // ECALL/EBREAK
            rs1_needed = 0;
            rs2_needed = 0;
            halt = 1;
        end
        default: begin
            illegal_instruction = 1;
            halt = 1;
        end
    endcase
end

endmodule