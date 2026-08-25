# A Simple RV64I 5 Stage In-order Single Core CPU


The goal of this project was to gain a deeper understanding of pipelining. In pursuit of this goal and to keep the work that I was doing on topic, AI was used to generate testing infrastructure and sparingly for debugging.

The stages of the pipeline are instruction fetch, instruction decode, execute, memory, and write back (IF/ID/EX/MEM/WB).

The processor was built in 3 main stages. First I made a single cycle processor, then divided it into pipelines, then implemented all of the logic to ensure correctness along with some other finishing touches.

----------------------------------------------------------------------------------------------------------------------

At a high level:

In the IF stage, a request to load the instruction stored at the current pc is sent to the instruction memory.

In the ID stage, the instruction arrives and is processed by the control unit to generate the control signals. Additionally the register file is read and a sign extender processes any immediate values.

In the EX stage, the ALU performs any needed operation and a separate comparator generates a signal that determines if a conditional branch should be taken. The comparator is needed so that the ALU can be repurposed to calculate the target address for branches.

In the MEM stage, data is read/written to data memory and the next pc is calculated. The next pc defaults to pc + 4, but can be set to the destination of a jump/branch.

In the WB stage, it is determined what should be written to the register file, if anything. The result of a possible data read is muxed with the result from the alu and the current pc + 4.  

----------------------------------------------------------------------------------------------------------------------

To ensure proper behavior, the following measures are taken:

There is a freeze flag that when raised freezes the IF,ID, and EX stages, letting the MEM and WB stages complete.

There is a halt flag that holds everything in place in order to implement ECALL/EBREAK.

There is a reset signal that ensures no state elements are affected by any in flight values.

There is a flush flag that is set high if a branch misprediction is detected in the EX stage which makes instructions in IF and ID no ops while high. The flush flag is reset in the mem stage when the correct next pc is assigned.

There is a retire buffer to make sure that values that need to be forwarded don't fall out of the pipeline. It also allows faster forwarding and allows for the register file to be written on the positive edge instead of a negative edge (a stale value will be read in ID, which was prevented by negedge writing, but the correct value will be forwarded from the retire buffer in EX).

There is a forwarding unit in the EX stage which looks at inflight instructions in the EX/MEM pipeline register, the MEM/WB pipeline register, and the retire buffer to determine if an operand needs a value forwarded to make sure canonical register values are being used.

There is also a forwarding unit in the MEM stage which forwards values from the WB stage for stores.

There is a hazard unit in the EX which stalls the pipeline if what needs forwarding isn't ready to be forwarded (i.e. load use).

----------------------------------------------------------------------------------------------------------------------

Some notes on design choices:

In order to close timing, forwarding loaded values from the writeback stage was prohibited. Instead the pipeline will stall and the value will be forwarded from the retire buffer. This reduced the period from 20ns to 16ns because in the WB stage a loaded value is coming from bram, meaning a huge delay in fetching the data. Additionally the forwarding was coming after two muxes, all of this made it the critical path by far. The retire buffer can be synthesized with flip flops, meaning it is much faster to load from. On the other hand it introduces a 1 cycle penalty for load-use at distance 2 and raises the penalty for load-use at distance 1 from 1 to 2 cycles.

The next PC logic is in MEM, when it could be in EX. This causes an extra no-op on mispredicted branches, but was done to avoid a long path in EX. I didn't test whether it could fit or not, so this is a potential place for improvement.

When there is a jump or branch, the target address is calculated by the ALU, which means muxing together more signals. There could have been a separate unit to do this calculation, and the result could have been carried through to the mem stage. Doing this would potentially reduce the critical path by taking the ALU out, but I chose to make it simple by reusing the ALU. Another potential place for improvement.

Trap handling was implemented in a very basic way. There is no trap handling or mepc, mcause, mtval, mtvec, just a halt and illegal instruction flag. This was done to keep the scope of the project focused on pipelining.

Branches are always predicted not taken, i.e. no branch predictor. This was to keep the project simple.

## Results

To verify the correctness of my design, I ran the official riscv-tests rv64ui suite plus a directed test suite with a golden-model generator and cycle-budget performance regressions. All rv64ui tests pass with fence_i and ma_data skipped by construction, and all directed tests pass as well.

To evaluate the efficacy of the pipelining, I synthesized it in vivado using an arty a7-100t (7a100t-csg324) board as the basis for static timing analysis. I then optimized the design to reduce the critical path from ~20ns and close timing at 16ns (62.5MHz). I also found the avg CPI from my directed test suite to be 1.194 when discounting initial pipline fill. Therefore a primitive estimate of MIPS (mega instructions per second) is 52.

Excerpts from the vivado utilization report:

```
1. Slice Logic
--------------

+----------------------------+------+-------+------------+-----------+-------+
|          Site Type         | Used | Fixed | Prohibited | Available | Util% |
+----------------------------+------+-------+------------+-----------+-------+
| Slice LUTs*                | 2518 |     0 |          0 |     63400 |  3.97 |
|   LUT as Logic             | 2430 |     0 |          0 |     63400 |  3.83 |
|   LUT as Memory            |   88 |     0 |          0 |     19000 |  0.46 |
|     LUT as Distributed RAM |   88 |     0 |            |           |       |
|     LUT as Shift Register  |    0 |     0 |            |           |       |
| Slice Registers            |  801 |     0 |          0 |    126800 |  0.63 |
|   Register as Flip Flop    |  801 |     0 |          0 |    126800 |  0.63 |
|   Register as Latch        |    0 |     0 |          0 |    126800 |  0.00 |
| F7 Muxes                   |   70 |     0 |          0 |     31700 |  0.22 |
| F8 Muxes                   |    0 |     0 |          0 |     15850 |  0.00 |
| Unique Control Sets        |   13 |       |          0 |     15850 |  0.08 |
+----------------------------+------+-------+------------+-----------+-------+

2. Memory
---------

+-------------------+------+-------+------------+-----------+-------+
|     Site Type     | Used | Fixed | Prohibited | Available | Util% |
+-------------------+------+-------+------------+-----------+-------+
| Block RAM Tile    |   18 |     0 |          0 |       135 | 13.33 |
|   RAMB36/FIFO*    |   16 |     0 |          0 |       135 | 11.85 |
|     RAMB36E1 only |   16 |       |            |           |       |
|   RAMB18          |    4 |     0 |          0 |       270 |  1.48 |
|     RAMB18E1 only |    4 |       |            |           |       |
+-------------------+------+-------+------------+-----------+-------+
```

## Authors

Jack Robbennolt  
    - JackRobbennolt@gmail.com
