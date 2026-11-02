# sys9.S: "FP unavailable" (0x800) and "VMX unavailable" (0xF20) raised in the VM (the JIT does not leave it, as for sc):
# fadd, lfd, stfd, vaddubm, lvx and mfvscr with the bit clear, in supervisor and user mode; and, in one block, an FP and a
# VMX instruction that pass with the bit set, mtmsr clearing it, the same instructions again: the JIT checks once a
# block and must check again after the mtmsr. G4 (PT_G4=1, VMX). Bare metal; the reference is the journal
# tests/epicycle/ref/sys9.bin (the interpreter, ptv -i -s); the JIT (pt; ptv with PT_VMSC=2) must give it word for word.
# Journal and handler as in sys7.S (the handler logs the vector, SRR0, SRR1, the MSR in the handler, DAR, DSISR).
        .set RES, 0x10000
        .macro LOG r
        stw \r, 0(%r31)
        addi %r31, %r31, 4
        .endm
        .macro MARK n
        lis %r3, 0x7e57
        ori %r3, %r3, \n
        LOG %r3
        .endm
        .macro LI32 r, v
        lis \r, (\v)@h
        ori \r, \r, (\v)@l
        .endm
        .macro RESUME lbl, msr
        LI32 %r29, \lbl
        LI32 %r28, \msr
        .endm
        .macro VEC off, hi
        .org \off
        li %r3, \off + \hi
        ba common
        .endm
        .macro TABLE hi
        VEC 0x200, \hi
        VEC 0x300, \hi
        VEC 0x400, \hi
        VEC 0x500, \hi
        VEC 0x600, \hi
        VEC 0x700, \hi
        VEC 0x800, \hi
        VEC 0x900, \hi
        VEC 0xa00, \hi
        VEC 0xb00, \hi
        VEC 0xc00, \hi
        VEC 0xd00, \hi
        VEC 0xe00, \hi
        VEC 0xf00, \hi
        VEC 0xf20, \hi                 # VMX unavailable
        VEC 0x1000, \hi
        VEC 0x1100, \hi
        VEC 0x1200, \hi
        VEC 0x1300, \hi
        VEC 0x1400, \hi
        VEC 0x1500, \hi
        VEC 0x1600, \hi
        VEC 0x1700, \hi
        .endm
        .macro USER lbl                 # enter user mode (PR=1, IR=DR=0) at lbl
        LI32 %r4, \lbl
        mtsrr0 %r4
        li %r4, 0x4000
        mtsrr1 %r4
        rfi
        .endm

        .globl reset
        .section .rom, "ax"              # 0xFFF00000: reset and the vectors for MSR.IP=1
        .org 0x100
reset:  LI32 %r3, 0xfff04000              # copy .vec and .text from ROM to RAM at 0
        li %r4, 0
        LI32 %r5, ram_end
0:      lwz %r6, 0(%r3)
        stw %r6, 0(%r4)
        addi %r3, %r3, 4
        addi %r4, %r4, 4
        cmplw %r4, %r5
        blt 0b
        sync
        isync
        lis %r31, RES@h
        MARK 0
        mfmsr %r4
        LOG %r4                           # MSR after reset
        MARK 1                           # sc with IP=1 -> 0xFFF00C00
        RESUME t1, 0x40
        sc
t1:     LI32 %r4, start
        mtctr %r4
        bctr
        TABLE 1

        .section .vec, "ax"              # 0x00000000: the vectors for MSR.IP=0
        TABLE 0

        .text
common: srwi %r30, %r31, 12                # loop guard: the journal stops at RES+4K
        cmplwi %r30, RES >> 12
        bgt die
        LOG %r3
        mfsrr0 %r30
        LOG %r30
        mfsrr1 %r30
        LOG %r30
        mfmsr %r30
        LOG %r30
        mfspr %r30, 19
        LOG %r30
        mfspr %r30, 18
        LOG %r30
        mtsrr0 %r29
        mtsrr1 %r28
        rfi
die:    b die

start:  MARK 2                           # clear IP
        li %r4, 0
        mtmsr %r4
        isync
        .set FP, 0x2000
        .set VECB, 0x02000000
        LI32 %r7, 0x20000                # a 16-byte aligned buffer
        MARK 3                           # FP=VEC=0, supervisor: each instruction raises its exception
        RESUME a1, 0
        fadd %f1, %f1, %f1
a1:     RESUME a2, 0
        lfd %f1, 0(%r7)
a2:     RESUME a3, 0
        stfd %f1, 8(%r7)
a3:     RESUME a4, 0
        vaddubm %v1, %v1, %v1
a4:     RESUME a5, 0
        lvx %v1, 0, %r7
a5:     RESUME a6, 0
        mfvscr %v1
a6:     MARK 4                           # one block: pass with the bit set, mtmsr clears it, the same instruction raises
        LI32 %r4, FP|VECB
        mtmsr %r4
        li %r5, 0
        RESUME b1, FP|VECB
        fadd %f2, %f1, %f1
        mtmsr %r5
        fadd %f3, %f1, %f1
b1:     mtmsr %r4
        RESUME b2, FP|VECB
        vaddubm %v2, %v1, %v1
        mtmsr %r5
        vaddubm %v3, %v1, %v1
b2:     li %r4, 0x7777
        LOG %r4
        MARK 5                           # user mode with FP=VEC=0, then with both set (no exception), back by sc
        RESUME u1n, 0x4000
        LI32 %r4, u1
        mtsrr0 %r4
        li %r4, 0x4000
        mtsrr1 %r4
        rfi
u1:     fadd %f1, %f1, %f1
u1n:    RESUME u2n, 0x4000
        vaddubm %v1, %v1, %v1
u2n:    RESUME u3, 0
        sc
u3:     LI32 %r4, u4
        mtsrr0 %r4
        LI32 %r4, 0x4000|FP|VECB
        mtsrr1 %r4
        RESUME u5, 0
        rfi
u4:     fadd %f1, %f1, %f1
        vaddubm %v1, %v1, %v1
        sc
u5:     MARK 0xee
        b .
