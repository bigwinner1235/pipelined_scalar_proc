module RegFile (
    input write_enable, clk,
    input [4:0] rs1,rs2,rd,
    input [63:0] w,
    output [63:0] a,b
);
//regs
reg [63:0] regs [31:1];

//use continuous assignment to drive output busses:
assign a = (rs1 == 5'd0) ? 64'd0 : regs[rs1];
assign b = (rs2 == 5'd0) ? 64'd0 : regs[rs2];

always @ (posedge clk) //retire stage forwarding allows posedge write
begin
    //write if enabled and target not XZR
    if (write_enable && !(rd == 5'd0))
           regs[rd] <= w; //write to reg with write bus
end
endmodule