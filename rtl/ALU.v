// add support for comparison opps
module ALU (
    input  [63:0] a, b,
    input  [3:0]  ctrl,
    input         word,
    output reg [63:0] result
);
    reg [63:0] r64;
    reg [31:0] r32;
    wire [31:0] aw = a[31:0], bw = b[31:0];

    always @(*) begin
        case (ctrl)
            4'd0: r64 = a + b;
            4'd1: r64 = a - b;
            4'd2: r64 = a << b[5:0];
            4'd3: r64 = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            4'd4: r64 = (a < b) ? 64'd1 : 64'd0;
            4'd5: r64 = a ^ b;
            4'd6: r64 = a >> b[5:0];
            4'd7: r64 = $signed(a) >>> b[5:0];
            4'd8: r64 = a | b;
            4'd9: r64 = a & b;
            4'd10: r64 = b;
            default: r64 = 64'd0;
        endcase

        case (ctrl)
            4'd0: r32 = aw + bw;
            4'd1: r32 = aw - bw;
            4'd2: r32 = aw << bw[4:0];
            4'd6: r32 = aw >> bw[4:0];
            4'd7: r32 = $signed(aw) >>> bw[4:0];
            default: r32 = 32'd0;
        endcase

        result = word ? {{32{r32[31]}}, r32} : r64;
    end
endmodule