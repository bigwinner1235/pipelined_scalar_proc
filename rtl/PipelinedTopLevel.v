module SingleCycleTopLevel (
    input reset,  //Active High
	input [63:0] startpc,
    input clk
);
//-----------------------------------------IF-----------------------------------------
reg [63:0] currentpc;
wire [63:0] nextpc;
wire [63:0] pc_plus_4;

always @(posedge clk) begin
    if(reset)
        currentpc <= startpc;
    else
        currentpc <= nextpc;
end    

//Instruction Memory
wire [31:0] instruction;
InstructionMemory imem(
    .address(currentpc),
    .inst(instruction)
);

reg [63:0] id_currentpc;
reg [31:0] id_instruction;

reg [63:0] ex_currentpc;
reg [31:0] ex_instruction;

reg [63:0] mem_currentpc;
reg [31:0] mem_instruction;

reg [63:0] wb_currentpc;
reg [31:0] wb_instruction;
reg        wb_reg_write;

assign pc_plus_4 = currentpc + 64'd4;

always @ (posedge clk) begin
    if(reset) begin
        //insert no ops
        id_currentpc    <=   64'h00000013;
        id_instruction  <=   32'h00000013; 
        ex_currentpc    <=   64'h00000013;
        ex_instruction  <=   32'h00000013;
        mem_currentpc   <=   64'h00000013;
        mem_instruction <=   32'h00000013;
        wb_currentpc    <=   64'h00000013;
        wb_instruction  <=   32'h00000013;
    end
    else begin
        id_currentpc    <=   currentpc;
        id_instruction  <=   instruction;

        ex_currentpc    <=   id_currentpc;
        ex_instruction  <=   id_instruction;

        mem_currentpc    <=  ex_currentpc;
        mem_instruction  <=  ex_instruction;

        wb_currentpc    <=   mem_currentpc;
        wb_instruction  <=   mem_instruction;
    end
end
//-----------------------------------------ID-----------------------------------------
//control signals
wire reg_write;
wire mem_write;
wire mem_read;
wire reg_write_src; //select from alu result and result of a mem read
wire alu_a_src; //select between current pc and reg file
wire alu_b_src; //feed alu operand b from sign extender or reg file
wire cond_br; //if there is a condition branch
wire jump; //set up for a jump (mux pc+4 with reg write bus)
wire word; //for alu
wire [2:0] sign_format;
wire [3:0] alu_op;
ControlUnit control(
    .opcode(id_instruction[6:0]),
    .funct3(id_instruction[14:12]),
    .funct7(id_instruction[31:25]),
    .reg_write(reg_write),
    .mem_write(mem_write),
    .mem_read(mem_read),
    .reg_write_src(reg_write_src),
    .alu_a_src(alu_a_src),
    .alu_b_src(alu_b_src),
    .cond_br(cond_br),
    .jump(jump),
    .word(word),
    .sign_format(sign_format),
    .alu_op(alu_op)
);

//Regfile
wire [63:0] reg_w_bus;
wire [63:0] a;
wire [63:0] b;
RegFile regfile(
    .write_enable(wb_reg_write),
    .clk(clk),
    .rs1(id_instruction[19:15]),
    .rs2(id_instruction[24:20]),
    .rd(wb_instruction[11:7]),
    .w(reg_w_bus),
    .a(a),
    .b(b)
);

//Sign Extender
wire[63:0] sign_ext_out;
SignExtender sign_ext(
    .instruction(id_instruction[31:7]),
    .format(sign_format),
    .result(sign_ext_out)
);

reg         ex_reg_write;
reg         ex_mem_write;
reg         ex_mem_read;
reg         ex_reg_write_src; //select from alu result and result of a mem read
reg         ex_alu_a_src; //select between current pc and reg file
reg         ex_alu_b_src; //feed alu operand b from sign extender or reg file
reg         ex_cond_br; //if there is a condition branch
reg         ex_jump; //set up for a jump (mux pc+4 with reg write bus)
reg         ex_word; //for alu
reg [3:0]   ex_alu_op;
reg [63:0]  ex_a;
reg [63:0]  ex_b;
reg [63:0]  ex_sign_ext_out;

reg         mem_reg_write;
reg         mem_mem_write;
reg         mem_mem_read;
reg         mem_reg_write_src; //select from alu result and result of a mem read
reg         mem_cond_br; //if there is a condition branch
reg         mem_jump; //set up for a jump (mux pc+4 with reg write bus)

reg         wb_reg_write_src; //select from alu result and result of a mem read
reg         wb_cond_br; //if there is a condition branch
reg         wb_jump; //set up for a jump (mux pc+4 with reg write bus)


always @ (posedge clk) begin
    if(reset)begin
        ex_reg_write        <=  1'b0;
        ex_mem_write        <=  1'b0; 
        ex_mem_read         <=  1'b0;
        ex_reg_write_src    <=  1'b0;
        ex_alu_a_src        <=  1'b0;
        ex_alu_b_src        <=  1'b0; 
        ex_cond_br          <=  1'b0;
        ex_jump             <=  1'b0;
        ex_word             <=  1'b0;
        ex_alu_op           <=  1'b0; 
        ex_a                <=  1'b0;
        ex_b                <=  1'b0;
        ex_sign_ext_out     <=  1'b0; 
        mem_reg_write       <=  1'b0; 
        mem_mem_write       <=  1'b0; 
        mem_mem_read        <=  1'b0;
        mem_reg_write_src   <=  1'b0; 
        mem_cond_br         <=  1'b0; 
        mem_jump            <=  1'b0; 
        wb_reg_write        <=  1'b0; 
        wb_reg_write_src    <=  1'b0;
        wb_cond_br          <=  1'b0; 
        wb_jump             <=  1'b0; 
    end
    else begin
        ex_reg_write        <=  reg_write;
        ex_mem_write        <=  mem_write;
        ex_mem_read         <=  mem_read;
        ex_reg_write_src    <=  reg_write_src; //select from alu result and result of a mem read
        ex_alu_a_src        <=  alu_a_src; //select between current pc and reg file
        ex_alu_b_src        <=  alu_b_src; //feed alu operand b from sign extender or reg file
        ex_cond_br          <=  cond_br; //if there is a condition branch
        ex_jump             <=  jump; //set up for a jump (mux pc+4 with reg write bus)
        ex_word             <=  word; //for alu
        ex_alu_op           <=  alu_op;
        ex_a                <=  a;
        ex_b                <=  b;
        ex_sign_ext_out     <=  sign_ext_out;

        mem_reg_write        <=  ex_reg_write;
        mem_mem_write        <=  ex_mem_write;
        mem_mem_read         <=  ex_mem_read;
        mem_reg_write_src    <=  ex_reg_write_src; //select from alu result and result of a mem read
        mem_cond_br          <=  ex_cond_br; //if there is a condition branch
        mem_jump             <=  ex_jump; //set up for a jump (mux pc+4 with reg write bus)

        wb_reg_write        <=   mem_reg_write;
        wb_reg_write_src    <=   mem_reg_write_src; //select from alu result and result of a mem read
        wb_cond_br          <=   mem_cond_br; //if there is a condition branch
        wb_jump             <=   mem_jump; //set up for a jump (mux pc+4 with reg write bus)
    end
end

//-----------------------------------------EX-----------------------------------------

//ALU
wire [63:0] alu_in_a;
wire [63:0] alu_in_b;
wire [63:0] alu_out;

assign alu_in_a = (ex_alu_a_src)? ex_currentpc : ex_a;
assign alu_in_b = (ex_alu_b_src)? ex_sign_ext_out : ex_b;

ALU alu(
    .a(alu_in_a),
    .b(alu_in_b),
    .ctrl(ex_alu_op),
    .word(ex_word),
    .result(alu_out)
);

//Comparator
wire comp_true;
Comparator comp(
    .funct3(ex_instruction[14:12]),
    .a(ex_a),
    .b(ex_b),
    .taken(comp_true)
);

reg         mem_comp_true;
reg [63:0]  mem_alu_out;
reg [63:0]  mem_b;
reg         wb_comp_true;
reg [63:0]  wb_alu_out;
always @ (posedge clk) begin
    mem_comp_true   <=  comp_true;
    mem_alu_out     <=  alu_out;
    mem_b           <=  ex_b;

    wb_comp_true   <=  mem_comp_true;
    wb_alu_out     <=  mem_alu_out;
end
//-----------------------------------------MEM-----------------------------------------

//Data mem
wire [63:0] mem_data_out;
DataMemory data_mem(
    .write_enable(mem_mem_write),
    .read_enable(mem_mem_read), 
    .clk(clk),
    .address(mem_alu_out), 
    .data_in(mem_b),
    .funct3(mem_instruction[14:12]),
    .data_out(mem_data_out)
);


reg [63:0] wb_mem_data_out;
always @ (posedge clk) begin
    wb_mem_data_out         <= mem_data_out;
end
//-----------------------------------------WB-----------------------------------------
wire [63:0] from_post_mem_mux;
assign from_post_mem_mux = (wb_reg_write_src)? wb_mem_data_out : wb_alu_out;
assign reg_w_bus = (wb_jump)? (wb_currentpc + 64'd4) : from_post_mem_mux;

assign nextpc = (wb_jump || (wb_cond_br && wb_comp_true))? {wb_alu_out[63:1],1'b0} : pc_plus_4;
endmodule
