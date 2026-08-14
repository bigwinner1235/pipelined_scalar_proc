#Claude wrote this
#!/usr/bin/env python3
"""Generate the test suite: assembles each program, runs it through a
sequential RV64I golden model, and writes prog.hex (commented) +
expected.txt (final value of every stored address)."""
import os, shutil

REPO = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.join(REPO, "tests")
M64 = (1 << 64) - 1

def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v

# ---------------------------------------------------------------- encoders
def enc_r(op, f3, f7, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_i(op, f3, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def enc_s(f3, rs1, rs2, imm):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23
def enc_b(f3, rs1, rs2, imm):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
         | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63
def enc_u(op, rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
def enc_j(rd, imm):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) \
         | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F

R_OPS = {'add':(0x33,0,0x00),'sub':(0x33,0,0x20),'sll':(0x33,1,0),'slt':(0x33,2,0),
         'sltu':(0x33,3,0),'xor':(0x33,4,0),'srl':(0x33,5,0),'sra':(0x33,5,0x20),
         'or':(0x33,6,0),'and':(0x33,7,0),
         'addw':(0x3B,0,0),'subw':(0x3B,0,0x20),'sllw':(0x3B,1,0),
         'srlw':(0x3B,5,0),'sraw':(0x3B,5,0x20)}
I_OPS = {'addi':(0x13,0),'slti':(0x13,2),'sltiu':(0x13,3),'xori':(0x13,4),
         'ori':(0x13,6),'andi':(0x13,7),'addiw':(0x1B,0)}
SHIFTS = {'slli':(0x13,1,0x00),'srli':(0x13,5,0x00),'srai':(0x13,5,0x20),
          'slliw':(0x1B,1,0x00),'srliw':(0x1B,5,0x00),'sraiw':(0x1B,5,0x20)}
LOADS = {'lb':0,'lh':1,'lw':2,'ld':3,'lbu':4,'lhu':5,'lwu':6}
STORES = {'sb':0,'sh':1,'sw':2,'sd':3}
BRANCHES = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

# every opcode ControlUnit.v decodes. a .word whose opcode is outside this set
# is guaranteed to fall into the decoder's default arm (illegal_instruction).
KNOWN_OPCODES = {0x33,0x3B,0x13,0x1B,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x73}

def reg(t):
    assert t.startswith('x'), t
    n = int(t[1:]); assert 0 <= n < 32
    return n

# ---------------------------------------------------------------- assembler
def assemble(src):
    """src: list of lines 'label: mnem ops  # note'. Returns list of
    (word, display_text) plus label dict."""
    # pass 1: addresses
    labels, insts = {}, []
    for line in src:
        line = line.strip()
        if not line:
            continue
        text = line
        if ':' in line.split('#')[0]:
            lbl, rest = line.split(':', 1)
            labels[lbl.strip()] = len(insts) * 4
            line = rest.strip()
            if not line:
                continue
        insts.append((line, text))

    def imm_val(tok, pc, relative):
        tok = tok.strip()
        try:
            return int(tok, 0)
        except ValueError:
            pass
        if '-' in tok:
            a, b = tok.split('-')
            return labels[a.strip()] - labels[b.strip()]
        return labels[tok] - (pc if relative else 0)

    out = []
    for idx, (line, text) in enumerate(insts):
        pc = idx * 4
        asm = line.split('#')[0].strip()
        note = line.split('#', 1)[1].strip() if '#' in line else ''
        toks = asm.replace(',', ' ').split()
        m = toks[0]
        if m == 'nop':
            w = enc_i(0x13, 0, 0, 0, 0)
        elif m == 'halt':
            w = enc_j(0, 0)                       # jal x0, 0 (self-loop)
            asm = 'jal x0, 0'
            note = note or 'halt (self-loop)'
        elif m == 'ecall':
            w = 0x00000073
        elif m == 'ebreak':
            w = 0x00100073
        elif m == '.word':                        # raw encoding, for illegal instructions
            w = imm_val(toks[1], pc, False) & 0xFFFFFFFF
            assert (w & 0x7F) not in KNOWN_OPCODES, \
                f'.word 0x{w:08x} decodes to a known opcode, it is not illegal'
            note = note or 'reserved opcode: illegal'
        elif m in R_OPS:
            op, f3, f7 = R_OPS[m]
            w = enc_r(op, f3, f7, reg(toks[1]), reg(toks[2]), reg(toks[3]))
        elif m in I_OPS:
            op, f3 = I_OPS[m]
            imm = imm_val(toks[3], pc, False)
            assert -2048 <= imm < 2048, asm
            w = enc_i(op, f3, reg(toks[1]), reg(toks[2]), imm)
        elif m in SHIFTS:
            op, f3, f7 = SHIFTS[m]
            sh = imm_val(toks[3], pc, False)
            w = enc_i(op, f3, reg(toks[1]), reg(toks[2]), (f7 << 5) | sh)
        elif m in LOADS:
            off, base = toks[2].rstrip(')').split('(')
            w = enc_i(0x03, LOADS[m], reg(toks[1]), reg(base), imm_val(off, pc, False))
        elif m in STORES:
            off, base = toks[2].rstrip(')').split('(')
            w = enc_s(STORES[m], reg(base), reg(toks[1]), imm_val(off, pc, False))
        elif m in BRANCHES:
            imm = imm_val(toks[3], pc, True)
            w = enc_b(BRANCHES[m], reg(toks[1]), reg(toks[2]), imm)
        elif m == 'jal':
            w = enc_j(reg(toks[1]), imm_val(toks[2], pc, True))
        elif m == 'jalr':
            off, base = toks[2].rstrip(')').split('(')
            w = enc_i(0x67, 0, reg(toks[1]), reg(base), imm_val(off, pc, False))
        elif m in ('lui', 'auipc'):
            w = enc_u(0x37 if m == 'lui' else 0x17, reg(toks[1]), imm_val(toks[2], pc, False))
        else:
            raise ValueError('unknown mnemonic: ' + asm)
        out.append((w, asm, note, text))
    return out, labels

# ---------------------------------------------------------------- golden model
def simulate(prog, labels):
    """Returns (stores, halt, illegal): the final value of every stored address,
    plus the expected end-of-run state of the core's halt / illegal flags."""
    def const(tok):
        try:
            return int(tok, 0)
        except ValueError:
            if '-' in tok:
                a, b = tok.split('-')
                return labels[a.strip()] - labels[b.strip()]
            return labels[tok]
    x = [0] * 32
    mem = {}
    stored = []          # ordered unique store addresses (all 8-aligned here)
    halt = illegal = False
    pc, steps = 0, 0
    while steps < 100000:
        steps += 1
        idx = pc // 4
        assert 0 <= idx < len(prog), f'pc 0x{pc:x} out of program'
        w, asm, note, _ = prog[idx]
        toks = asm.replace(',', ' ').split()
        m = toks[0]
        nxt = pc + 4
        def rv(t): return x[reg(t)]
        if m == 'nop':
            pass
        elif m in R_OPS or m in I_OPS or m in SHIFTS:
            rd = reg(toks[1]); a = rv(toks[2])
            if m in R_OPS:
                b = rv(toks[3])
            else:
                b = const(toks[3]) & M64 if m in SHIFTS else sx(const(toks[3]), 64) & M64
            def op64(name, a, b):
                sa, sb = sx(a, 64), sx(b, 64)
                if name in ('add','addi','addw','addiw'):   return a + b
                if name in ('sub','subw'):                  return a - b
                if name in ('sll','slli','sllw','slliw'):   return a << (b & 63)
                if name in ('slt','slti'):                  return int(sa < sb)
                if name in ('sltu','sltiu'):                return int((a & M64) < (b & M64))
                if name in ('xor','xori'):                  return a ^ b
                if name in ('srl','srli','srlw','srliw'):   return (a & M64) >> (b & 63)
                if name in ('sra','srai','sraw','sraiw'):   return sa >> (b & 63)
                if name in ('or','ori'):                    return a | b
                if name in ('and','andi'):                  return a & b
                raise ValueError(name)
            if m in ('addw','subw','sllw','srlw','sraw','addiw','slliw','srliw','sraiw'):
                a32, b32 = a & 0xFFFFFFFF, b & 0xFFFFFFFF
                sh = b & 31
                if m in ('addw','addiw'): r32 = a32 + b32
                elif m == 'subw':          r32 = a32 - b32
                elif m in ('sllw','slliw'): r32 = a32 << sh
                elif m in ('srlw','srliw'): r32 = a32 >> sh
                else:                       r32 = sx(a32, 32) >> sh   # sraw/sraiw
                res = sx(r32, 32) & M64
            else:
                res = op64(m, a, b) & M64
            if rd: x[rd] = res
        elif m in LOADS:
            off, base = toks[2].rstrip(')').split('(')
            addr = (rv(base) + sx(int(off, 0), 64)) & M64
            size = 1 << (LOADS[m] & 3)
            raw = 0
            for k in range(size):
                raw |= mem.get(addr + k, 0) << (8 * k)
            val = raw if LOADS[m] >> 2 or size == 8 else sx(raw, size * 8) & M64
            rd = reg(toks[1])
            if rd: x[rd] = val
        elif m in STORES:
            off, base = toks[2].rstrip(')').split('(')
            addr = (rv(base) + sx(int(off, 0), 64)) & M64
            val = rv(toks[1])
            for k in range(1 << STORES[m]):
                mem[addr + k] = (val >> (8 * k)) & 0xFF
            if addr not in stored:
                stored.append(addr)
        elif m in BRANCHES:
            a, b = rv(toks[1]), rv(toks[2])
            sa, sb = sx(a, 64), sx(b, 64)
            take = {'beq': a == b, 'bne': a != b, 'blt': sa < sb,
                    'bge': sa >= sb, 'bltu': a < b, 'bgeu': a >= b}[m]
            if take:
                nxt = pc + branch_off(w)
        elif m == 'jal':
            tgt = pc + jal_off(w)
            if tgt == pc:
                break                                     # halt
            rd = reg(toks[1])
            if rd: x[rd] = (pc + 4) & M64
            nxt = tgt
        elif m == 'jalr':
            off, base = toks[2].rstrip(')').split('(')
            tgt = (rv(base) + sx((w >> 20) & 0xFFF, 12)) & M64 & ~1
            rd = reg(toks[1])
            if rd: x[rd] = (pc + 4) & M64
            nxt = tgt
        elif m in ('lui', 'auipc'):
            rd = reg(toks[1])
            imm = sx((w >> 12) & 0xFFFFF, 20) << 12
            if rd: x[rd] = (imm if m == 'lui' else pc + imm) & M64
        elif m in ('ecall', 'ebreak'):
            halt = True                                   # architectural halt
            break
        elif m == '.word':
            halt = illegal = True                         # illegal instruction traps
            break
        else:
            raise ValueError(asm)
        pc = nxt
    else:
        raise RuntimeError('golden model did not halt')

    def read64(a):
        return sum(mem.get(a + k, 0) << (8 * k) for k in range(8))
    return [(a, read64(a)) for a in sorted(stored)], halt, illegal

def branch_off(w):
    return sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) |
              (((w >> 25) & 0x3F) << 5) | (((w >> 8) & 0xF) << 1), 13)
def jal_off(w):
    return sx(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) |
              (((w >> 20) & 1) << 11) | (((w >> 21) & 0x3FF) << 1), 21)

# ---------------------------------------------------------------- output
def emit(name, src, max_cycles=None, zero_addrs=()):
    """zero_addrs: addresses the program must leave untouched. The golden model
    only records addresses it actually stored to, so a store that wrongly
    commits past a halt would otherwise go unchecked."""
    prog, labels = assemble(src)
    expected, halt, illegal = simulate(prog, labels)
    have = {a for a, _ in expected}
    expected += [(a, 0) for a in zero_addrs if a not in have]
    expected.sort()
    d = os.path.join(TESTS, name)
    os.makedirs(d)
    with open(os.path.join(d, 'flags.txt'), 'w', newline='\n') as f:
        f.write('# halt illegal\n')
        f.write(f'{int(halt)} {int(illegal)}\n')
    if max_cycles is not None:
        with open(os.path.join(d, 'max_cycles.txt'), 'w', newline='\n') as f:
            f.write(f'{max_cycles}\n')
    with open(os.path.join(d, 'prog.hex'), 'w', newline='\n') as f:
        for w, asm, note, _ in prog:
            bs = ' '.join(f'{(w >> (8*k)) & 0xFF:02x}' for k in range(4))
            line = f'{bs}  // {asm}'
            if note:
                line = f'{bs}  // {asm:<22} -- {note}'
            f.write(line + '\n')
    with open(os.path.join(d, 'expected.txt'), 'w', newline='\n') as f:
        f.write('# addr             value\n')
        for a, v in expected:
            f.write(f'{a:016x}   {v:016x}\n')
    print(f'{name}: {len(prog)} instructions, {len(expected)} checked addresses, '
          f'halt={int(halt)} illegal={int(illegal)}')

def blk(*lines):
    return list(lines)

NOPS4 = ['nop', 'nop', 'nop', 'nop']

# ---------------------------------------------------------------- programs
isa = blk(
    'addi x1, x0, -5    # x1 = 0xfffffffffffffffb',
    'addi x2, x0, 3     # x2 = 3',
    'lui x4, 0x80000    # x4 = 0xffffffff80000000',
    'nop', 'nop',
    # R-type
    'add x10, x1, x2',
    'sub x11, x1, x2',
    'sll x12, x2, x2',
    'slt x13, x1, x2',
    'sltu x14, x1, x2',
    'xor x15, x1, x2',
    'srl x16, x1, x2',
    'sra x17, x1, x2',
    'or x18, x1, x2',
    'and x19, x1, x2',
    'sd x10, 0(x0)',
    'sd x11, 8(x0)',
    'sd x12, 16(x0)',
    'sd x13, 24(x0)',
    'sd x14, 32(x0)',
    'sd x15, 40(x0)',
    'sd x16, 48(x0)',
    'sd x17, 56(x0)',
    'sd x18, 64(x0)',
    'sd x19, 72(x0)',
    # R-type word + I-type
    'addw x10, x4, x2',
    'subw x11, x4, x2',
    'sllw x12, x2, x2',
    'srlw x13, x4, x2',
    'sraw x14, x4, x2',
    'addi x15, x1, 10',
    'slti x16, x1, 0',
    'sltiu x17, x1, -1',
    'xori x18, x1, 255',
    'ori x19, x2, 240',
    'andi x20, x1, 255',
    'slli x21, x1, 4',
    'srli x22, x1, 4',
    'srai x23, x1, 4',
    'sd x10, 80(x0)',
    'sd x11, 88(x0)',
    'sd x12, 96(x0)',
    'sd x13, 104(x0)',
    'sd x14, 112(x0)',
    'sd x15, 120(x0)',
    'sd x16, 128(x0)',
    'sd x17, 136(x0)',
    'sd x18, 144(x0)',
    'sd x19, 152(x0)',
    'sd x20, 160(x0)',
    'sd x21, 168(x0)',
    'sd x22, 176(x0)',
    'sd x23, 184(x0)',
    # I-type word + U-type
    'addiw x10, x4, -1',
    'slliw x11, x2, 4',
    'srliw x12, x4, 1',
    'sraiw x13, x4, 1',
    'auipc x14, 1',
    'sd x10, 192(x0)',
    'sd x11, 200(x0)',
    'sd x12, 208(x0)',
    'sd x13, 216(x0)',
    'sd x14, 224(x0)',
    'sd x4, 232(x0)     # check the lui result',
    # stores of every size, then load them back every way
    'sd x1, 512(x0)',
    'sb x1, 520(x0)',
    'sh x1, 528(x0)',
    'sw x1, 536(x0)',
    'ld x10, 512(x0)',
    'lw x11, 512(x0)',
    'lwu x12, 512(x0)',
    'lh x13, 512(x0)',
    'lhu x14, 512(x0)',
    'lb x15, 512(x0)',
    'lbu x16, 512(x0)',
    'sd x10, 240(x0)',
    'sd x11, 248(x0)',
    'sd x12, 256(x0)',
    'sd x13, 264(x0)',
    'sd x14, 272(x0)',
    'sd x15, 280(x0)',
    'sd x16, 288(x0)',
    # branches: taken branch skips 4 nop delay slots + a canary clobber
    'addi x9, x0, 1',
    'beq x2, x2, T1',
    *NOPS4,
    'addi x9, x0, 666   # skipped if beq works',
    'T1: sd x9, 296(x0)',
    'addi x9, x0, 2',
    'bne x1, x2, T2',
    *NOPS4,
    'addi x9, x0, 666   # skipped if bne works',
    'T2: sd x9, 304(x0)',
    'addi x9, x0, 3',
    'blt x1, x2, T3',
    *NOPS4,
    'addi x9, x0, 666   # skipped if blt works',
    'T3: sd x9, 312(x0)',
    'addi x9, x0, 4',
    'bge x2, x1, T4',
    *NOPS4,
    'addi x9, x0, 666   # skipped if bge works',
    'T4: sd x9, 320(x0)',
    'addi x9, x0, 5',
    'bltu x2, x1, T5',
    *NOPS4,
    'addi x9, x0, 666   # skipped if bltu works',
    'T5: sd x9, 328(x0)',
    'addi x9, x0, 6',
    'bgeu x1, x2, T6',
    *NOPS4,
    'addi x9, x0, 666   # skipped if bgeu works',
    'T6: sd x9, 336(x0)',
    # jal
    'addi x9, x0, 7',
    'jal x10, T7',
    *NOPS4,
    'addi x9, x0, 666   # skipped if jal works',
    'T7: sd x9, 344(x0)',
    'sd x10, 352(x0)    # jal link value',
    # jalr
    'A1: auipc x11, 0',
    'addi x9, x0, 8',
    'nop', 'nop',
    'jalr x12, T8-A1(x11)',
    *NOPS4,
    'addi x9, x0, 666   # skipped if jalr works',
    'T8: sd x9, 360(x0)',
    'sd x12, 368(x0)    # jalr link value',
    # end through the architectural halt, not a self-loop: the whole ISA sweep
    # must leave illegal_instruction clear, and ecall must raise halt
    'ecall',
)

hz_raw_ex = blk(
    'addi x1, x0, 5',
    'addi x2, x1, 1     # RAW distance 1: needs EX->EX forward',
    'nop', 'nop', 'nop',
    'sd x2, 64(x0)',
    'halt',
)

hz_raw_mem = blk(
    'addi x1, x0, 7',
    'nop',
    'addi x2, x1, 1     # RAW distance 2: needs MEM->EX forward',
    'nop', 'nop', 'nop',
    'sd x2, 64(x0)',
    'halt',
)

hz_raw_wb = blk(
    'addi x1, x0, 9',
    'nop', 'nop',
    'addi x2, x1, 1     # RAW distance 3: reads regfile while WB writes it',
    'nop', 'nop', 'nop',
    'sd x2, 64(x0)',
    'halt',
)

hz_load_use = blk(
    'addi x1, x0, 42',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'ld x2, 64(x0)',
    'addi x3, x2, 1     # load-use: needs a stall, forwarding alone cannot fix',
    'nop', 'nop', 'nop',
    'sd x3, 72(x0)',
    'halt',
)

hz_store_data = blk(
    'addi x1, x0, 55',
    'sd x1, 64(x0)      # store data RAW distance 1: needs forward into rs2 path',
    'halt',
)

hz_branch_flush = blk(
    'addi x1, x0, 1',
    'beq x0, x0, T      # always taken',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'T: sd x1, 64(x0)',
    'halt',
)

hz_jal_flush = blk(
    'addi x1, x0, 1',
    'jal x0, T',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'T: sd x1, 64(x0)',
    'halt',
)

hz_jalr_flush = blk(
    'addi x1, x0, 1',
    'addi x5, x0, T     # x5 = target address',
    'nop', 'nop', 'nop',
    'jalr x0, 0(x5)',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'addi x1, x0, 666   # wrong path: must be flushed',
    'T: sd x1, 64(x0)',
    'halt',
)

hz_store_data_d2 = blk(
    'addi x1, x0, 55',
    'nop',
    'sd x1, 64(x0)      # store data RAW distance 2: EX->EX forward must reach mem_b',
    'halt',
)

hz_load_store = blk(
    'addi x1, x0, 42',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'nop', 'nop', 'nop',
    'ld x2, 64(x0)',
    'sd x2, 72(x0)      # store data comes straight from the load',
    'halt',
)

hz_load_branch = blk(
    'addi x2, x0, 0     # give x2 a known stale value',
    'addi x1, x0, 1',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'nop', 'nop', 'nop',
    'ld x2, 64(x0)      # x2 = 1',
    'beq x2, x0, BAD    # stale x2 (0) says taken, real x2 (1) says not taken',
    'addi x3, x0, 7',
    'nop', 'nop', 'nop',
    'sd x3, 72(x0)',
    'halt',
    'BAD: addi x3, x0, 666',
    'sd x3, 72(x0)',
    'halt',
)

hz_load_jalr = blk(
    'addi x6, x0, 0     # known stale value',
    'addi x5, x0, T',
    'nop', 'nop', 'nop',
    'sd x5, 64(x0)',
    'nop', 'nop', 'nop',
    'ld x6, 64(x0)',
    'jalr x0, 0(x6)     # load-use into jalr',
    'addi x1, x0, 666   # wrong path',
    'addi x1, x0, 666   # wrong path',
    'T: addi x1, x0, 9',
    'nop', 'nop', 'nop',
    'sd x1, 72(x0)',
    'halt',
)

hz_branch_next = blk(
    'addi x1, x0, 5',
    'nop', 'nop', 'nop',
    'beq x0, x0, N      # taken, target is the very next instruction',
    'N: addi x1, x1, 1  # must execute exactly once',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'halt',
)

hz_needed_stage = blk(
    'addi x2, x0, 0     # known stale value for x2',
    'addi x1, x0, 7',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'nop', 'nop', 'nop',
    'ld x2, 64(x0)      # x2 = 7',
    'addi x3, x2, 1     # true load-use: must freeze',
    'lui x4, 1          # in ID during the hazard; the hazard unit must use the EX-stage rs_needed, not this one',
    'nop', 'nop', 'nop',
    'sd x3, 72(x0)',
    'halt',
)

# two control transfers in flight at once: a jump-to-next takes the no-flush
# path, so a taken branch 0/1/2 slots behind it coexists with it in the pipe
hz_jalnext_0 = blk(
    'addi x3, x0, 0',
    'jal x1, N          # target = next instruction: no-flush path',
    'N: beq x0, x0, T   # taken branch right behind it',
    'addi x3, x0, 666   # wrong path',
    'addi x3, x0, 666   # wrong path',
    'nop', 'nop',
    'T: sd x3, 64(x0)',
    'sd x1, 72(x0)      # jal link value',
    'halt',
)

hz_jalnext_1 = blk(
    'addi x3, x0, 0',
    'jal x1, N          # target = next instruction: no-flush path',
    'N: nop',
    'beq x0, x0, T      # in EX while the jal is further down the pipe',
    'addi x3, x0, 666   # wrong path',
    'addi x3, x0, 666   # wrong path',
    'nop', 'nop',
    'T: sd x3, 64(x0)',
    'sd x1, 72(x0)',
    'halt',
)

hz_jalnext_2 = blk(
    'addi x3, x0, 0',
    'jal x1, N          # target = next instruction: no-flush path',
    'N: nop',
    'nop',
    'beq x0, x0, T',
    'addi x3, x0, 666   # wrong path',
    'addi x3, x0, 666   # wrong path',
    'nop', 'nop',
    'T: sd x3, 64(x0)',
    'sd x1, 72(x0)',
    'halt',
)

# perf regressions: these carry a max_cycles budget and fail if a false
# stall or extra branch penalty creeps back in. Budgets are exact for the
# current pipeline (MEM-stage redirect, format-aware hazard unit); update
# them deliberately when the pipeline changes.
perf_falsefreeze = blk(
    'ld x2, 64(x0)',
    'addi x3, x0, 2     # independent, but imm bits [24:20] read as "x2"',
    'nop', 'nop', 'nop',
    'sd x3, 72(x0)',
    'halt',
)

perf_load_store = blk(
    'addi x1, x0, 42',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'nop', 'nop', 'nop',
    'ld x2, 64(x0)',
    'sd x2, 72(x0)      # store data from load: MEM forward, no stall needed',
    'halt',
)

perf_loop8 = blk(
    'addi x1, x0, 8     # counter',
    'addi x2, x0, 0',
    'L: addi x2, x2, 1',
    'addi x1, x1, -1',
    'bne x1, x0, L',
    'nop', 'nop', 'nop',
    'sd x2, 64(x0)',
    'halt',
)

# traps. The three instructions after the trap are exactly the ones that reach
# IF/ID/EX before the halt flag latches -- if the halt does not hold the
# pipeline, one of their stores commits and the zero checks catch it.
trap_ecall = blk(
    'addi x1, x0, 0x55',
    'addi x2, x0, 666   # poison',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)      # retires before the trap: must commit',
    'ecall              # halt = 1, illegal = 0',
    'sd x2, 64(x0)      # past the halt: must not commit',
    'sd x2, 72(x0)      # past the halt: must not commit',
    'sd x2, 80(x0)      # past the halt: must not commit',
)

trap_ebreak = blk(
    'addi x1, x0, 0x55',
    'addi x2, x0, 666   # poison',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)      # retires before the trap: must commit',
    'ebreak             # halt = 1, illegal = 0',
    'sd x2, 64(x0)      # past the halt: must not commit',
    'sd x2, 72(x0)      # past the halt: must not commit',
    'sd x2, 80(x0)      # past the halt: must not commit',
)

trap_illegal = blk(
    'addi x1, x0, 0x55',
    'addi x2, x0, 666   # poison',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)      # retires before the trap: must commit',
    '.word 0x0000007f   # opcode 1111111 is reserved: halt = 1, illegal = 1',
    'sd x2, 64(x0)      # past the halt: must not commit',
    'sd x2, 72(x0)      # past the halt: must not commit',
    'sd x2, 80(x0)      # past the halt: must not commit',
)

# an illegal instruction on a mispredicted path is never executed, so it must
# not latch illegal_instruction: the flush has to kill the trap too
trap_illegal_flushed = blk(
    'addi x1, x0, 1',
    'beq x0, x0, T      # always taken',
    '.word 0x0000007f   # wrong path: flushed, must not raise illegal',
    '.word 0x0000007f   # wrong path: flushed, must not raise illegal',
    '.word 0x0000007f   # wrong path: flushed, must not raise illegal',
    '.word 0x0000007f   # wrong path: flushed, must not raise illegal',
    'T: sd x1, 64(x0)',
    'ecall              # halt = 1, illegal = 0',
)

hz_x0 = blk(
    'addi x0, x0, 7     # write to x0 is discarded',
    'addi x1, x0, 0     # x0 must read 0: a naive forwarder would give 7',
    'nop', 'nop', 'nop',
    'sd x1, 64(x0)',
    'halt',
)

if __name__ == '__main__':
    if os.path.isdir(TESTS):
        shutil.rmtree(TESTS)
    os.makedirs(TESTS)
    emit('isa', isa)
    emit('hz_raw_ex', hz_raw_ex)
    emit('hz_raw_mem', hz_raw_mem)
    emit('hz_raw_wb', hz_raw_wb)
    emit('hz_load_use', hz_load_use)
    emit('hz_store_data', hz_store_data)
    emit('hz_store_data_d2', hz_store_data_d2)
    emit('hz_load_store', hz_load_store)
    emit('hz_load_branch', hz_load_branch)
    emit('hz_load_jalr', hz_load_jalr)
    emit('hz_branch_next', hz_branch_next)
    emit('hz_needed_stage', hz_needed_stage)
    emit('hz_jalnext_0', hz_jalnext_0)
    emit('hz_jalnext_1', hz_jalnext_1)
    emit('hz_jalnext_2', hz_jalnext_2)
    emit('perf_falsefreeze', perf_falsefreeze, max_cycles=10)
    emit('perf_load_store', perf_load_store, max_cycles=14)
    emit('perf_loop8', perf_loop8, max_cycles=55)
    emit('hz_branch_flush', hz_branch_flush)
    emit('hz_jal_flush', hz_jal_flush)
    emit('hz_jalr_flush', hz_jalr_flush)
    emit('hz_x0', hz_x0)
    emit('trap_ecall', trap_ecall, zero_addrs=[72, 80])
    emit('trap_ebreak', trap_ebreak, zero_addrs=[72, 80])
    emit('trap_illegal', trap_illegal, zero_addrs=[72, 80])
    emit('trap_illegal_flushed', trap_illegal_flushed)
