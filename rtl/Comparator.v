module Comparator (
    input [2:0] funct3,
    input [63:0] a,b,
    output reg taken
);
always @(*) begin
    case(funct3)
    3'b000: taken = (a == b)? 1'b1 : 1'b0; //beq
    3'b001: taken = (a != b)? 1'b1 : 1'b0; //bne
    3'b100: taken = ($signed(a) < $signed(b))? 1'b1 : 1'b0; //blt
    3'b110: taken = (a < b)? 1'b1 : 1'b0; //bltu
    3'b101: taken = ($signed(a) >= $signed(b))? 1'b1 : 1'b0; //bge
    3'b111: taken = (a >= b)? 1'b1 : 1'b0; //bgeu
    default: taken = 1'b0;
    endcase
end   
endmodule