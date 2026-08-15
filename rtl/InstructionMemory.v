module InstructionMemory #(parameter ADDR_BITS = 16) (
    input  clk,
    input  enable,
    input  [63:0] address,
    output reg [31:0] inst
);
reg [7:0] mem [0:(1<<ADDR_BITS)-1];
wire [ADDR_BITS-1:0] a = address[ADDR_BITS-1:0];
always @(posedge clk) begin
    if(enable)
        inst <= {mem[a+3'd3], mem[a+3'd2], mem[a+3'd1], mem[a+3'd0]};
end
endmodule