# sys7.S: twi, the trap in the VM (the JIT raises it without leaving the VM, as sc): every TO bit, true and false, signed
# and unsigned, negative immediates, TO 0, a trap loop, the vector at 0xFFF00700 (IP=1) and a trap from user mode.
# Bare metal; the reference is the journal tests/epicycle/ref/sys7.bin (the interpreter, ptv -i -s); the JIT on ptv must give it word for word.
# Journal: %r31 -> RES, LOG writes a word. Before each expected exception: %r29 = where to return, %r28 = with which MSR.
# The handler clobbers only %r3 and %r30. `common` logs: the vector number (odd: the 0xFFF0xxxx table), SRR0, SRR1, the MSR in the handler, DAR, DSISR.
# Build (zig = clang/lld): python3 -m ziglang cc -target powerpc-freestanding-none -mcpu=750 -c -o sys1.o sys1.S
#                          python3 -m ziglang ld.lld -N -e reset -T sys.ld -o sys1.elf sys1.o  (GNU as/ld work too)
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
        MARK 0x70                        # TO 31 in a loop: a trap every time, back into the same block
        li %r20, 0
loop1:  RESUME l1n, 0
        twi 31, %r0, 0x10
l1n:    addi %r20, %r20, 1
        cmplwi %r20, 4
        blt loop1
        LOG %r20
        MARK 0x71                        # each TO bit, true then false
        LI32 %r5, -7
        RESUME a1, 0
        twi 4, %r5, -7                   # equal -> trap
a1:     twi 4, %r5, 7                    # not equal: no trap
        RESUME a2, 0
        twi 16, %r5, -6                  # -7 < -6 signed -> trap
a2:     twi 8, %r5, -6                   # -7 > -6 signed: no trap
        RESUME a3, 0
        twi 1, %r5, 5                    # 0xFFFFFFF9 > 5 unsigned -> trap
a3:     twi 2, %r5, 5                    # 0xFFFFFFF9 < 5 unsigned: no trap
        li %r6, 3
        RESUME a4, 0
        twi 2, %r6, -1                   # 3 < 0xFFFFFFFF unsigned -> trap
a4:     twi 24, %r6, 3                   # less or greater (not equal): no trap
        RESUME a5, 0
        twi 24, %r6, 4                   # 3 < 4 -> trap
a5:     twi 0, %r6, 3                    # TO 0: never
        LI32 %r4, 0x5a5a
        LOG %r4
        MARK 0x72                        # IP=1: the trap's vector is 0xFFF00700
        li %r4, 0x40
        mtmsr %r4
        isync
        RESUME a6, 0x40
        twi 31, %r0, 1
a6:     li %r4, 0
        mtmsr %r4
        isync
        MARK 0x73                        # a trap from user mode (PR=1): SRR1 keeps PR
        RESUME a7, 0
        USER u7
u7:     twi 31, %r1, 2
a7:     MARK 0xee                        # end
        b .
