/* SPDX-License-Identifier: GPL-2.0-or-later */
/* VAP_PVS_CONST_CNTL (0x22d4) PVS_CONST_BASE_OFFSET 7:0 through the real constant upload: a direct and an A0-relative
 * read of logical constant 5 both see physical vector 512 + base + 5, the base is read per draw (program cache warm,
 * only CONST_CNTL changed), and base 0 keeps the old mapping. Leopard's ATI driver uses base 128 (Tiger's 0).
 * Negative control: OPTICS_PVS_CONST_BASE=0 (the pre-fix mapping) must fail the base-128 assertion.
 * AI-generated (Claude), 2026-11-04. */
#include "draw.h"
#include "r300_state.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static uint32_t regs[0x10000/4];
static void wr(OpticsR300State *s,unsigned a,uint32_t v){regs[a/4]=v;(void)optics_r300_write(s,a,v);}
static uint32_t u(float f){uint32_t x;memcpy(&x,&f,4);return x;}
/* PVS source word: type 1:0 (1 input, 2 constant), relative 4, index 12:5, swizzles from 13 (4 = 0), ADDR_SEL 30:29. */
static uint32_t src(unsigned type,unsigned idx,unsigned rel,unsigned sx,unsigned sy,unsigned sz,unsigned sw){
    return type|rel<<4|idx<<5|sx<<13|sy<<16|sz<<19|sw<<22;}
static void build(OpticsR300State *s,uint32_t cntl,float want_x,float want_y){
    static const uint32_t p[13]={4u|3u<<4|3u<<16,0,0,0,0x40000000,0x3f800000,0,0,0x40000000,0,0x3f800000,0,0x40000000};
    OpticsDraw d;const char *why=NULL;OpticsVertexOut out[3];
    wr(s,0x22d4,cntl);
    if(!optics_draw_build(&d,regs,s,0x35,p,13,NULL,NULL,NULL,&why)){fprintf(stderr,"build: %s\n",why);assert(0);}
    assert(d.pvs_constants==256);   /* relative addressing: the whole logical bank */
    if(!optics_draw_vertices(&d,out,&why)){fprintf(stderr,"vertices: %s\n",why);assert(0);}
    for(unsigned v=0;v<3;v++){
        fprintf(stderr,"CONST_CNTL %#010x vertex %u: direct %g relative %g (want %g %g)\n",cntl,v,out[v].window[0],out[v].window[1],want_x,want_y);
        assert(out[v].window[0]==want_x);   /* direct c[5].x */
        assert(out[v].window[1]==want_y);   /* c[3 + A0.x].y with A0.x = 2 */
    }
    optics_draw_free(&d);
}
int main(void){
    OpticsR300State *s=optics_r300_state_create(1);assert(s);
    /* Target, fragment program and one FLOAT_4 stream into input 0, as optics-draw-decode. */
    wr(s,0x43e0,1440|1440u<<13);wr(s,0x43e4,1503|1503u<<13);wr(s,0x20b4,4);wr(s,0x2150,3u|1u<<13);
    wr(s,0x21e0,0xf000|1u<<3|2u<<6|3u<<9);wr(s,0x2090,1);wr(s,0x4e38,6u<<21|64);wr(s,0x4e04,0x38);wr(s,0x4e08,0);
    const uint32_t fs[]={0,0,0,0,0,0,0x400000,0,7u<<26,1u<<24,(21u<<7)|(20u<<14),9u|(17u<<7)|(16u<<14)};
    const unsigned head[]={0x4600,0x4604,0x4608,0x4610,0x4614,0x4618,0x461c,0x4620,0x46c0,0x47c0,0x48c0,0x49c0};
    for(unsigned k=0;k<12;k++)wr(s,head[k],fs[k]);
    /* PVS on (no bypass); VTE: no perspective divide, no viewport, so window x,y are the position output x,y. */
    wr(s,0x2140,0);wr(s,0x20b0,0x300);
    /* Program at PVS_FIRST_INST 128 (Leopard's bank), three instructions:
     *   ARL  A0.x      = in0.w            (2.0)
     *   ADD  out0.xyzw = c[5] + 0         (direct)
     *   ADD  out0.y    = c[3 + A0.x] + 0  (relative, logical 5) */
    const uint32_t code[12]={
        13u|1u<<8|1u<<20,           src(1,0,0,3,3,3,3),0,0,
        3u|2u<<8|15u<<20,           src(2,5,0,0,1,2,3),src(2,5,0,4,4,4,4),0,
        3u|2u<<8|2u<<20,            src(2,3,1,0,1,2,3),src(2,3,0,4,4,4,4),0};
    wr(s,0x2200,128);for(unsigned k=0;k<12;k++)wr(s,0x2208,code[k]);
    wr(s,0x22d0,128u|130u<<10|130u<<20);wr(s,0x22d8,0);wr(s,0x22dc,0);
    /* Constant memory: physical vector 512+j holds (j, j+0.5, 0, 1), so every bank and offset is distinguishable. */
    wr(s,0x2200,512);
    for(unsigned j=0;j<1024;j++){wr(s,0x2208,u((float)j));wr(s,0x2208,u((float)j+0.5f));wr(s,0x2208,0);wr(s,0x2208,u(1));}
    /* PVS_MAX_CONST_ADDR (23:16) set to 255 so the case stays valid if that limit is modelled later. */
    build(s,0x00ff0000,5,5.5f);       /* base 0: vector 517 */
    build(s,0x00ff0080,133,133.5f);   /* base 128: vector 645; only CONST_CNTL changed, program cache warm */
    build(s,0x00ff0000,5,5.5f);       /* back to base 0 */
    optics_r300_state_destroy(s);
    puts("PASS: PVS constant base offset, direct and A0-relative, refreshed per draw");return 0;
}
