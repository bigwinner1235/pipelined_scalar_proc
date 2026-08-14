//Claude wrote this
// Testbench for the official riscv-tests rv64ui suite (built with the
// custom env in riscv_env/). Differences from tb_top.v:
//   - the program image is one unified memory (code + data), so the same
//     hex is loaded into both imem and dmem
//   - termination is the architectural halt flag (env's PASS/FAIL = ecall);
//     there is no self-loop convention here
//   - pass/fail comes from gp (x3): 1 = pass, >= 2 = failing sub-test
`timescale 1ns/1ps
module tb_riscv;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  PipelinedTopLevel dut (
    .clk(clk),
    .reset(rst),
    .startpc(64'd0)
  );

  localparam MAX_CYCLES = 50000;

  reg [1023:0] hexfile;
  integer cycles, i;
  reg halted;
  reg [63:0] gp;

  initial begin
    if (!$value$plusargs("hex=%s", hexfile)) begin
      $display("ERROR: no +hex given");
      $finish;
    end

    // clear, then load the image into instruction memory
    for (i = 0; i < (1<<16); i = i + 1)
      dut.imem.mem[i] = 8'h00;
    $readmemh(hexfile, dut.imem.mem);

    if ($test$plusargs("vcd")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_riscv);
    end

    // hold reset, then release on a negedge so the release is clean
    repeat (4) @(posedge clk);
    @(negedge clk);
    // load data memory here, not at time 0: the core executes instruction 0
    // repeatedly while reset is held, so any stores it does must be wiped.
    for (i = 0; i < (1<<16); i = i + 1)
      dut.data_mem.mem[i] = 8'h00;
    $readmemh(hexfile, dut.data_mem.mem);
    rst = 0;

    // run until the core halts (ecall from RVTEST_PASS/FAIL), or time out
    halted = 1'b0;
    for (cycles = 0; cycles < MAX_CYCLES && !halted; cycles = cycles + 1) begin
      @(negedge clk);
      if (dut.halt === 1'b1) halted = 1'b1;
    end

    if (!halted) begin
      $display("  core did not halt within %0d cycles", MAX_CYCLES);
      $display("TEST FAILED (timeout)");
      $finish;
    end

    gp = dut.regfile.regs[3];
    $display("  program finished in %0d cycles (halt=%b illegal=%b gp=%0d)",
             cycles, dut.halt, dut.illegal, gp);

    if (gp === 64'd1) $display("TEST PASSED");
    else              $display("TEST FAILED (sub-test %0d)", gp);
    $finish;
  end
endmodule
