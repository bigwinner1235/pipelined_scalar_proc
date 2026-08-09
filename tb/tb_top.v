//Claude wrote this
`timescale 1ns/1ps
module tb_top;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  PipelinedTopLevel dut (
    .clk(clk),
    .reset(rst),
    .startpc(64'd0)
  );

  // every test program ends with "jal x0, 0" (a self-loop). when that
  // instruction reaches WB, every instruction before it has already
  // written back and any store it made has already committed in MEM.
  localparam [31:0] HALT_INST = 32'h0000006f;
  localparam        MAX_CYCLES = 10000;

  reg [1023:0] testdir, path;
  integer fd, r, errors, cycles, i, budget;
  reg [63:0] addr, expect_val, actual;
  reg halted;

  // read 8 bytes little-endian out of the byte-addressed data memory
  function [63:0] read_dmem(input [63:0] a);
    integer k;
    begin
      read_dmem = 64'd0;
      for (k = 0; k < 8; k = k + 1)
        read_dmem[8*k +: 8] = dut.data_mem.mem[a + k];
    end
  endfunction

  initial begin
    if (!$value$plusargs("testdir=%s", testdir)) begin
      $display("ERROR: no +testdir given");
      $finish;
    end

    // clear instruction memory so unfilled words read as 0, not X
    for (i = 0; i < (1<<16); i = i + 1)
      dut.imem.mem[i] = 8'h00;

    $sformat(path, "%0s/prog.hex", testdir);
    $readmemh(path, dut.imem.mem);

    if ($test$plusargs("vcd")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end

    // hold reset, then release on a negedge so the release is clean
    repeat (4) @(posedge clk);
    @(negedge clk);
    // clear data memory here, not at time 0: the core executes instruction 0
    // repeatedly while reset is held, so any stores it does must be wiped.
    for (i = 0; i < (1<<16); i = i + 1)
      dut.data_mem.mem[i] = 8'h00;
    rst = 0;

    // run until the halt instruction retires, or until we time out
    halted = 1'b0;
    for (cycles = 0; cycles < MAX_CYCLES && !halted; cycles = cycles + 1) begin
      @(negedge clk);
      if (dut.wb_instruction === HALT_INST) halted = 1'b1;
    end

    if (!halted) begin
      $display("  no halt (jal x0, 0) retired within %0d cycles", MAX_CYCLES);
      $display("TEST FAILED (timeout)");
      $finish;
    end

    $display("  program finished in %0d cycles", cycles);

    errors = 0;
    $sformat(path, "%0s/expected.txt", testdir);
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %0s", path);
      $finish;
    end

    while (!$feof(fd)) begin
      r = $fscanf(fd, " %h %h", addr, expect_val);
      if (r == 2) begin
        actual = read_dmem(addr);
        if (actual !== expect_val) begin
          $display("  mem[0x%h] = 0x%h, expected 0x%h", addr, actual, expect_val);
          errors = errors + 1;
        end
      end else begin
        r = $fgets(path, fd);
      end
    end
    $fclose(fd);

    // optional cycle budget: perf regression tests fail if they get slower
    $sformat(path, "%0s/max_cycles.txt", testdir);
    fd = $fopen(path, "r");
    if (fd != 0) begin
      r = $fscanf(fd, " %d", budget);
      $fclose(fd);
      if (r == 1 && cycles > budget) begin
        $display("  took %0d cycles, budget is %0d", cycles, budget);
        errors = errors + 1;
      end
    end

    if (errors == 0) $display("TEST PASSED");
    else                     $display("TEST FAILED (%0d mismatches)", errors);
    $finish;
  end
endmodule
