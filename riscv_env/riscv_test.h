//Claude wrote this
// Minimal test environment for the official riscv-tests rv64ui suite,
// replacing the standard env/p one. This core has no CSRs, so every boot
// and trap macro is empty; pass/fail report through gp (x3) and halt with
// ecall, which latches the core's architectural halt flag:
//   pass: gp = 1
//   fail: gp = number of the failing sub-test (always >= 2)
#ifndef _ENV_PIPELINED_SCALAR_TEST_H
#define _ENV_PIPELINED_SCALAR_TEST_H

#define RVTEST_RV64U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN \
    .section .text.init;  \
    .globl _start;        \
_start:

#define RVTEST_CODE_END

#define RVTEST_PASS \
    li TESTNUM, 1;  \
    ecall

#define RVTEST_FAIL \
    ecall

#define RVTEST_DATA_BEGIN .balign 8;
#define RVTEST_DATA_END

#endif
