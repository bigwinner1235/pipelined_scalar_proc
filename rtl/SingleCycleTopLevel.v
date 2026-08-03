module SingleCycleTopLevel (
    input reset,  //Active High
	input [63:0] startpc,
    input clk
);

reg [63:0] currentpc;
wire [63:0] nextpc;
wire [63:0] pc_plus_4;

assign pc_plus_4 = currentpc + 64'd4;

always @(posedge clk) begin
    if(reset)
        currentpc <= #3 startpc;
    else
        currentpc <= #3 nextpc;
end    

//Instruction Memory
wire [31:0] instruction;
InstructionMemory imem(
    .address(currentpc),
    .inst(instruction)
);

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
    .opcode(instruction[6:0]),
    .funct3(instruction[14:12]),
    .funct7(instruction[31:25]),
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
    .write_enable(reg_write),
    .clk(clk),
    .rs1(instruction[19:15]),
    .rs2(instruction[24:20]),
    .rd(instruction[11:7]),
    .w(reg_w_bus),
    .a(a),
    .b(b)
);

//Sign Extender
wire[63:0] sign_ext_out;
SignExtender sign_ext(
    .instruction(instruction[31:7]),
    .format(sign_format),
    .result(sign_ext_out)
);

//ALU
wire [63:0] alu_in_a;
wire [63:0] alu_in_b;
wire [63:0] alu_out;

assign alu_in_a = (alu_a_src)? currentpc : a;
assign alu_in_b = (alu_b_src)? sign_ext_out : b;

ALU alu(
    .a(alu_in_a),
    .b(alu_in_b),
    .ctrl(alu_op),
    .word(word),
    .result(alu_out)
);

//Comparator
wire comp_true;
Comparator comp(
    .funct3(instruction[14:12]),
    .a(a),
    .b(b),
    .taken(comp_true)
);

//Data mem
wire [63:0] mem_data_out;
wire [63:0] from_post_mem_mux;
DataMemory data_mem(
    .write_enable(mem_write),
    .read_enable(mem_read), 
    .clk(clk),
    .address(alu_out), 
    .data_in(b),
    .funct3(instruction[14:12]),
    .data_out(mem_data_out)
);
assign from_post_mem_mux = (reg_write_src)? mem_data_out : alu_out;
assign reg_w_bus = (jump)? pc_plus_4 : from_post_mem_mux;

assign nextpc = (jump || (cond_br && comp_true))? {alu_out[63:1],1'b0} : pc_plus_4;
endmodule
