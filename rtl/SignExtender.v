module SignExtender (
    input      [31:7] instruction,
    input      [2:0]  format,
    output reg [63:0] result
);

localparam I_TYPE = 3'd0,
           S_TYPE = 3'd1,
           B_TYPE = 3'd2,
           U_TYPE = 3'd3,
           J_TYPE = 3'd4;

always @(*) begin
    case (format)
        I_TYPE: result = {{53{instruction[31]}},
                          instruction[30:25], instruction[24:21], instruction[20]};

        S_TYPE: result = {{53{instruction[31]}},
                          instruction[30:25], instruction[11:8], instruction[7]};

        B_TYPE: result = {{52{instruction[31]}}, instruction[7],
                          instruction[30:25], instruction[11:8], 1'b0};

        U_TYPE: result = {{32{instruction[31]}},
                          instruction[31:20], instruction[19:12], 12'b0};

        J_TYPE: result = {{44{instruction[31]}},
                          instruction[19:12], instruction[20],
                          instruction[30:25], instruction[24:21], 1'b0};

        default: result = 64'd0;
    endcase
end

endmodule