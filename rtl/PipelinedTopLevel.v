module PipelinedTopLevel (
    input           reset,  //Active High
	input [63:0]    startpc,
    input           clk
);
//----------------------------------------------------------------------------------IF signals
reg  [63:0] currentpc;
wire [63:0] pc_plus_4; //pc + 4 for the youngest instruction

//----------------------------------------------------------------------------------ID signals
wire        reg_write;
wire        mem_write;
wire        mem_read;
wire        reg_write_src; //1: data mem output, 0: alu output
wire        alu_a_src; //1: current pc, 0: reg out a
wire        alu_b_src; //1: immedeate gen, 0: reg out b
wire        cond_br; 
wire        jump;
wire        word; 
wire        rs1_needed; //for hazards
wire        rs2_needed; //for hazards
wire        illegal_instruction;
wire        trap;
wire [2:0]  sign_format;
wire [3:0]  alu_op;
wire [63:0] a;
wire [63:0] b;
wire [63:0] sign_ext_out;

//------------------------------------------------1----------------------------------EX signals
//cononical reg outputs(needed for comparator accuracy)
reg [63:0] post_alu_forwarding_a;
reg [63:0] post_alu_forwarding_b;

wire [63:0] alu_in_a;
wire [63:0] alu_in_b;
wire [63:0] alu_out;
wire        comp_true; //1 if condition for a branch is true
wire flush; //flag for flushing
wire redirect; //if a given instruction causes the next instruction to not be at pc+4

//----------------------------------------------------------------------------------MEM signals
wire [63:0] mem_data_out;
reg  [63:0] mem_data_in;

//----------------------------------------------------------------------------------WB signals
wire [63:0] from_post_mem_mux;
wire [63:0] reg_w_bus;
reg  [63:0] nextpc;
reg         freeze; // for a load-use dependency
reg         halt; //for ecall/ebreak
reg         illegal; //flag illegal instructions

//----------------------------------------------------------------------------------from IF to ID
reg  [63:0]  id_currentpc;
wire [31:0]  id_instruction;
reg          flushed_in_if; //to make flushes work properly

//----------------------------------------------------------------------------------from ID to EX
reg  [63:0] ex_currentpc;
reg  [31:0] ex_instruction;
reg         ex_reg_write;
reg         ex_mem_write;
reg         ex_mem_read;
reg         ex_reg_write_src;
reg         ex_alu_a_src;
reg         ex_alu_b_src;
reg         ex_cond_br;
reg         ex_jump;
reg         ex_word;
reg  [3:0]  ex_alu_op;
reg  [63:0] ex_a;
reg  [63:0] ex_b;
reg  [63:0] ex_sign_ext_out;
reg         ex_rs1_needed;
reg         ex_rs2_needed;
reg         ex_illegal_instruction;
reg         ex_trap;

//----------------------------------------------------------------------------------from EX to MEM
reg  [63:0] mem_currentpc;
reg  [31:0] mem_instruction;
reg         mem_reg_write;
reg         mem_mem_write;
reg         mem_mem_read;
reg         mem_reg_write_src;
reg         mem_cond_br;
reg         mem_jump;
reg         mem_comp_true;
reg  [63:0] mem_alu_out;
reg  [63:0] mem_b;
reg         mem_redirect;
reg         mem_illegal_instruction;
reg         mem_trap;

//----------------------------------------------------------------------------------from MEM to WB
reg  [63:0] wb_currentpc;
reg  [31:0] wb_instruction;
reg         wb_reg_write;
reg         wb_reg_write_src;
reg         wb_cond_br;
reg         wb_jump;
reg         wb_comp_true;
reg  [63:0] wb_alu_out;
reg  [63:0] wb_mem_data_out;
reg         wb_redirect;

//----------------------------------------------------------------------------------plumbing:
//signals from IF:
always @ (posedge clk) begin
    if ((!freeze && !halt) || reset) begin
        if(reset || flush) begin
            id_currentpc    <=   64'd0;
        end
        if(flush) begin
            flushed_in_if    <=   1'b1;
        end
        else begin
            id_currentpc    <=   currentpc;   
            flushed_in_if    <=   1'b0;
        end
    end
end

//signals from ID:
always @ (posedge clk) begin
    if ((!freeze && !halt) || reset) begin
        if(reset || flush || flushed_in_if)begin
            //control signals:
            ex_reg_write        <=  1'b0;
            ex_mem_write        <=  1'b0; 
            ex_mem_read         <=  1'b0;
            ex_reg_write_src    <=  1'b0;
            ex_alu_a_src        <=  1'b0;
            ex_alu_b_src        <=  1'b0; 
            ex_cond_br          <=  1'b0;
            ex_jump             <=  1'b0;
            ex_word             <=  1'b0;
            ex_alu_op           <=  4'b0; 
            ex_a                <=  1'b0;
            ex_b                <=  1'b0;
            ex_sign_ext_out     <=  1'b0;
            ex_rs1_needed       <=  1'b0;
            ex_rs2_needed       <=  1'b0;  
            ex_illegal_instruction <= 1'b0;
            ex_trap             <=  1'b0;      
        end
        else begin
            ex_currentpc        <=  id_currentpc;
            ex_instruction      <=  id_instruction;
            //control signals:
            ex_reg_write        <=  reg_write;
            ex_mem_write        <=  mem_write;
            ex_mem_read         <=  mem_read;
            ex_reg_write_src    <=  reg_write_src; 
            ex_alu_a_src        <=  alu_a_src;
            ex_alu_b_src        <=  alu_b_src;
            ex_cond_br          <=  cond_br;
            ex_jump             <=  jump; 
            ex_word             <=  word; 
            ex_alu_op           <=  alu_op;
            ex_a                <=  a;
            ex_b                <=  b;
            ex_sign_ext_out     <=  sign_ext_out;
            ex_rs1_needed       <=  rs1_needed;
            ex_rs2_needed       <=  rs2_needed;
            ex_illegal_instruction <= illegal_instruction;
            ex_trap             <=  trap;
        end
    end
end

//signals from EX:
always @ (posedge clk) begin
    if (!halt || reset) begin
        if(reset || freeze)begin
            //control signals:
            mem_reg_write       <=  1'b0; 
            mem_mem_write       <=  1'b0; 
            mem_mem_read        <=  1'b0;
            mem_reg_write_src   <=  1'b0; 
            mem_cond_br         <=  1'b0; 
            mem_jump            <=  1'b0;    
            mem_redirect        <=  1'b0;
            mem_illegal_instruction <=  1'b0;
            mem_trap            <=  1'b0;
        end
        else begin
            mem_currentpc       <=  ex_currentpc;
            mem_instruction     <=  ex_instruction;
            //control signals:
            mem_reg_write       <=  ex_reg_write;
            mem_mem_write       <=  ex_mem_write;
            mem_mem_read        <=  ex_mem_read;
            mem_reg_write_src   <=  ex_reg_write_src;
            mem_cond_br         <=  ex_cond_br;
            mem_jump            <=  ex_jump;
            //signals originated in EX:
            mem_comp_true       <=  comp_true;
            mem_alu_out         <=  alu_out;
            mem_b               <=  post_alu_forwarding_b;   
            mem_redirect        <=  redirect;
            mem_illegal_instruction <=  ex_illegal_instruction;
            mem_trap            <=  ex_trap;
        end
    end
end

//signals from MEM:
always @ (posedge clk) begin
    if (!halt || reset) begin
        if(reset)begin
            //control signals:
            wb_reg_write        <=  1'b0; 
            wb_reg_write_src    <=  1'b0;
            wb_cond_br          <=  1'b0; 
            wb_jump             <=  1'b0;
            wb_redirect         <=  1'b0; 
        end
        else begin
            wb_currentpc        <=  mem_currentpc;
            wb_instruction      <=  mem_instruction;
            //control signals:
            wb_reg_write        <=  mem_reg_write;
            wb_reg_write_src    <=  mem_reg_write_src;
            wb_cond_br          <=  mem_cond_br;
            wb_jump             <=  mem_jump;
            //signals originated in EX:
            wb_comp_true        <=  mem_comp_true;
            wb_alu_out          <=  mem_alu_out;
            //signals originated in MEM:
            wb_mem_data_out     <=  mem_data_out;
        end
    end
end

//-----------------------------------------IF-----------------------------------------
always @(posedge clk) begin
    if(!freeze || reset) begin
        if(reset)
            currentpc <= startpc;
        else
            currentpc <= nextpc;
    end
end    

InstructionMemory imem(
    .enable(!freeze && !halt),
    .clk(clk),
    .address(currentpc),
    .inst(id_instruction)
);

assign pc_plus_4 = currentpc + 64'd4;

//-----------------------------------------ID-----------------------------------------
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
    .alu_op(alu_op),
    .rs1_needed(rs1_needed),
    .rs2_needed(rs2_needed),
    .illegal_instruction(illegal_instruction),
    .halt(trap)
);

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

SignExtender sign_ext(
    .instruction(id_instruction[31:7]),
    .format(sign_format),
    .result(sign_ext_out)
);

//-----------------------------------------EX-----------------------------------------

//mux between reg file and alt alu inputs
assign alu_in_a = (ex_alu_a_src)? ex_currentpc : post_alu_forwarding_a;
assign alu_in_b = (ex_alu_b_src)? ex_sign_ext_out : post_alu_forwarding_b;

//forwarding unit
always@(*) begin
            //forward alu results from mem
            if((ex_instruction[19:15] == mem_instruction[11:7]) && (mem_instruction[11:7] != 5'd0) && mem_reg_write && !mem_reg_write_src) begin
                post_alu_forwarding_a = mem_alu_out;
            end
            //forward anything from wb
            else if((ex_instruction[19:15] == wb_instruction[11:7]) && (wb_instruction[11:7] != 5'd0) && wb_reg_write) begin
                post_alu_forwarding_a = reg_w_bus;
            end
            else 
                post_alu_forwarding_a = ex_a;
end
always@(*) begin
            //forward alu results from ex/mem pipeline reg
            if((ex_instruction[24:20] == mem_instruction[11:7]) && (mem_instruction[11:7] != 5'd0) && mem_reg_write && !mem_reg_write_src) begin
                post_alu_forwarding_b = mem_alu_out;
            end
            //forward anything from mem/wb pipeline reg
            else if((ex_instruction[24:20] == wb_instruction[11:7]) && (wb_instruction[11:7] != 5'd0) && wb_reg_write) begin
                post_alu_forwarding_b = reg_w_bus;
            end
            else 
                post_alu_forwarding_b = ex_b;
end

//hazard unit
always@(*) begin
    if((ex_instruction[19:15] == mem_instruction[11:7]) && (mem_instruction[11:7] != 5'd0) && mem_reg_write && mem_reg_write_src && ex_rs1_needed) begin
        freeze = 1'b1;
    end
    else if ((ex_instruction[24:20] == mem_instruction[11:7]) && (mem_instruction[11:7] != 5'd0) && mem_reg_write && mem_reg_write_src && !ex_mem_write && ex_rs2_needed) begin
        freeze = 1'b1;
    end
    else
        freeze = 1'b0;
end

assign redirect = (ex_jump || (ex_cond_br && comp_true)) && (id_currentpc != alu_out) && !freeze; //if there was a branch misprediction

ALU alu(
    .a(alu_in_a),
    .b(alu_in_b),
    .ctrl(ex_alu_op),
    .word(ex_word),
    .result(alu_out)
);

Comparator comp(
    .funct3(ex_instruction[14:12]),
    .a(post_alu_forwarding_a),
    .b(post_alu_forwarding_b),
    .taken(comp_true)
);

//-----------------------------------------MEM-----------------------------------------
//forwarding to write to memory
always@(*) begin
    if((mem_instruction[24:20] == wb_instruction[11:7]) && (wb_instruction[11:7] != 5'd0) && wb_reg_write) begin
        mem_data_in = reg_w_bus;
    end
    else 
        mem_data_in = mem_b;
end

DataMemory data_mem(
    .write_enable(mem_mem_write && !halt),
    .read_enable(mem_mem_read), 
    .clk(clk),
    .address(mem_alu_out), 
    .data_in(mem_data_in),
    .funct3(mem_instruction[14:12]),
    .data_out(mem_data_out)
);

//next PC logic:
assign flush = redirect || mem_redirect;
always @(*) begin
    if(mem_redirect)
        nextpc = {mem_alu_out[63:1],1'b0};
    else
        nextpc = pc_plus_4;
end

always @(posedge clk) begin
    if(reset)
        halt <= 1'b0;
    else if(mem_trap)
        halt <= 1'b1;
end
always @(posedge clk) begin
    if(reset)
        illegal <= 1'b0;
    else if(mem_illegal_instruction)
        illegal <= 1'b1;
end

//-----------------------------------------WB-----------------------------------------
assign from_post_mem_mux = (wb_reg_write_src)? wb_mem_data_out : wb_alu_out;
assign reg_w_bus = (wb_jump)? (wb_currentpc + 64'd4) : from_post_mem_mux;

endmodule
