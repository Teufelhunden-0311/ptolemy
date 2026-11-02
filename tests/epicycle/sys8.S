# sys8.S: icbi at DR=1 in the JIT, which finds the physical page through the ARM tables (AT in the VM; outside the VM,
# the interpreter). EA 0x20000000 -> page 0x200000 (PP=2) gets "li %r5, n; blr" at IR=DR=1, dcbst/sync/icbi/isync, and a
# call, four times in supervisor and four in user mode: the first call finds no translated code on the page, every later
# one must run the new words. Then the words change through EA 0x20000000 while icbi names EA 0x30000000 (SR3 = SR2: the
# same page), which no data access has touched, so no ARM entry holds it (the interpreter translates that icbi): the next
# call must run the new words. The interpreter (ptv -i -s) is the oracle; the JIT (pt; ptv with PT_VMSC=2 PT_VMRFI=2
# PT_VMMSR=2) must give the same journal word for word.
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
        .macro VEC off
        .org \off
        li %r3, \off
        ba common
        .endm
        .macro RFITO lbl, msr
        LI32 %r3, \lbl
        mtsrr0 %r3
        LI32 %r3, \msr
        mtsrr1 %r3
        rfi
        .endm
        .macro REAL                      # back to DR=0 from supervisor code
        li %r3, 0
        mtmsr %r3
        isync
        .endm
        .set DR, 0x10
        .set PR, 0x4000
        .set SRA, 0x20000102             # Kp=1, VSID 0x102
        .set EA, 0x20000000
        .set EA3, 0x30000000
        .set IR, 0x20

        .globl reset
        .section .rom, "ax"
        .org 0x100
reset:  LI32 %r3, 0xfff04000
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
        LI32 %r4, start
        mtctr %r4
        bctr

        .section .vec, "ax"
        VEC 0x200
        VEC 0x300
        VEC 0x400
        VEC 0x500
        VEC 0x600
        VEC 0x700
        VEC 0x800
        VEC 0x900
        VEC 0xc00
        VEC 0xd00
        VEC 0xf00
        VEC 0x1300

        .text
common: srwi %r30, %r31, 12
        cmplwi %r30, RES >> 12
        bgt die
        LOG %r3
        mfsrr0 %r30
        LOG %r30
        mfsrr1 %r30
        LOG %r30
        mfspr %r30, 19
        LOG %r30
        mfspr %r30, 18
        LOG %r30
        mtsrr0 %r29
        mtsrr1 %r28
        rfi
die:    b die

# pte_set: %r4 = EA, %r5 = word 1, %r6 = H, %r7 = slot -> %r11 = PTE address (as sys2.S). Clobbers %r8-%r12.
pte_set:
        mfsrin %r9, %r4
        rlwinm %r9, %r9, 0, 8, 31
        rlwinm %r10, %r4, 20, 16, 31
        rlwinm %r11, %r9, 0, 13, 31
        xor %r11, %r11, %r10
        cmpwi %r6, 0
        beq 1f
        not %r11, %r11
1:      rlwinm %r11, %r11, 6, 16, 25
        oris %r11, %r11, 0x0010
        rlwinm %r12, %r7, 3, 26, 28
        add %r11, %r11, %r12
        rlwinm %r12, %r9, 7, 1, 24
        oris %r12, %r12, 0x8000
        rlwimi %r12, %r6, 6, 25, 25
        rlwimi %r12, %r4, 10, 26, 31
        stw %r5, 4(%r11)
        sync
        stw %r12, 0(%r11)
        sync
        blr

start:  li %r4, 0
        mtmsr %r4
        isync
        MARK 1                           # real mode: HTAB, SDR1, SRs, BAT0 = 0-8 MB 1:1 for both keys
        LI32 %r4, 0x00100000
        li %r5, 0
        li %r6, 0x4000
        mtctr %r6
1:      stw %r5, 0(%r4)
        addi %r4, %r4, 4
        bdnz 1b
        LI32 %r4, 0x00100000
        mtspr 25, %r4
        li %r5, 0
        LI32 %r6, 0x20000100
2:      mtsrin %r6, %r5
        addis %r5, %r5, 0x1000
        addi %r6, %r6, 1
        cmplwi %r5, 0
        bne 2b
        li %r4, 0
        mtspr 528, %r4
        mtspr 529, %r4
        mtspr 530, %r4
        mtspr 531, %r4
        mtspr 532, %r4
        mtspr 533, %r4
        mtspr 534, %r4
        mtspr 535, %r4
        mtspr 536, %r4
        mtspr 537, %r4
        mtspr 538, %r4
        mtspr 539, %r4
        mtspr 540, %r4
        mtspr 541, %r4
        mtspr 542, %r4
        mtspr 543, %r4
        li %r5, 2
        mtspr 537, %r5
        mtspr 529, %r5
        li %r4, 0xff
        mtspr 536, %r4
        mtspr 528, %r4
        isync
        LI32 %r14, SRA
        mtsr 2, %r14                     # the same VSID in SR2 and SR3
        mtsr 3, %r14
        isync
        LI32 %r4, EA
        LI32 %r5, 0x00200002             # page 0x200000, PP=2
        li %r6, 0
        li %r7, 0
        bl pte_set
        MARK 2                           # supervisor, IR=DR=1: four rounds
        RFITO s2, IR|DR
s2:     li %r14, 0x100
        bl rounds
        REAL
        MARK 3                           # user mode: four rounds, then sc (the handler logs it, back in real mode)
        RESUME s3, 0
        RFITO u3, PR|IR|DR
u3:     li %r14, 0x200
        bl rounds
        sc
s3:     MARK 4                           # icbi through EA3, an alias no data access has touched
        RFITO s4, IR|DR
s4:     li %r4, 0x300
        LI32 %r6, EA
        LI32 %r7, EA3
        bl gen
        mtctr %r6
        bctrl
        LOG %r5
        REAL
        MARK 0xee
        b .

# rounds: four times gen("li %r5, %r14 + k") at EA, icbi EA, then a call to EA; logs %r5. Clobbers %r4-%r7, %r10, %r14-%r16, CTR.
rounds: mflr %r16
        li %r15, 4
1:      mr %r4, %r14
        LI32 %r6, EA
        mr %r7, %r6
        bl gen
        mtctr %r6
        bctrl
        LOG %r5
        addi %r14, %r14, 1
        addic. %r15, %r15, -1
        bne 1b
        mtlr %r16
        blr

# gen: "li %r5, %r4; blr" at %r6 (DR=1), dcbst, sync, icbi %r7, isync. Clobbers %r10.
gen:    oris %r10, %r4, 0x38a0
        stw %r10, 0(%r6)
        LI32 %r10, 0x4e800020
        stw %r10, 4(%r6)
        dcbst 0, %r6
        sync
        icbi 0, %r7
        isync
        blr
