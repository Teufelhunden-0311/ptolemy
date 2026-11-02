/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Vertex stream element decode of the R300 draw builder (BYTE, D3DCOLOR, SHORT, SIGNED/NORMALIZE). */
#include "../src/optics/draw.c"
#include <assert.h>
#include <stdio.h>
int main(void) {
    float r[4]; uint32_t w[4]={0x80ff4000,0x00017fff,0,0};
    decode_stream(4|1u<<15,0,w,r);   /* BYTE, NORMALIZE: x = bits 7:0 */
    assert(r[0]==0 && fabsf(r[1]-64/255.0f)<1e-6f && r[2]==1 && fabsf(r[3]-128/255.0f)<1e-6f);
    decode_stream(5|1u<<15,0,w,r);   /* D3DCOLOR: x,y,z = bytes 2,1,0 */
    assert(r[0]==1 && fabsf(r[1]-64/255.0f)<1e-6f && r[2]==0);
    decode_stream(4|1u<<14|1u<<15,1,w,r);   /* signed byte, method 1: 0x80 -> -1 (clamped), 0xff -> -1/127 */
    assert(r[3]==-1 && fabsf(r[2]+1/127.0f)<1e-6f);
    decode_stream(4|1u<<14|1u<<15,0,w,r);   /* method 0: 0x80 -> -128/127, below -1 */
    assert(fabsf(r[3]+128/127.0f)<1e-6f && fabsf(r[0]-0)<1e-6f);
    decode_stream(7,0,w,r);   /* SHORT_4, raw integers */
    assert(r[0]==0x4000 && r[1]==0x80ff && r[2]==0x7fff && r[3]==1);
    decode_stream(6|1u<<15,0,w,r);   /* SHORT_2 normalized; z,w default */
    assert(fabsf(r[0]-0x4000/65535.0f)<1e-6f && r[2]==0 && r[3]==1);
    decode_stream(1,0,w,r); assert(r[2]==0 && r[3]==1);   /* FLOAT_2 */
    assert(vap_swap(0x11223344,0)==0x11223344 && vap_swap(0x11223344,1)==0x22114433 && vap_swap(0x11223344,2)==0x44332211 && vap_swap(0x11223344,3)==0x33441122);
    {   /* DISCARD_SRC_PIXELS only with blending on (Halo's shadow blur: blending off, the field set, its zero pixels written) */
        static uint32_t regs[0x10000/4]; OpticsR300State *s=optics_r300_state_create(1); assert(s);
        #define WR(a,v) (regs[(a)/4]=(v),(void)optics_r300_write(s,(a),(v)))
        WR(0x43e0,1440|1440u<<13); WR(0x43e4,1503|1503u<<13); WR(0x2140,1u<<8); WR(0x20b4,4); WR(0x2150,3u|1u<<13);
        WR(0x21e0,0xf000|1u<<3|2u<<6|3u<<9); WR(0x2090,1); WR(0x4e38,6u<<21|64);
        const uint32_t fs[]={0,0,0,0,0,0,0x400000,0,7u<<26,1u<<24,(21u<<7)|(20u<<14),9u|(17u<<7)|(16u<<14)};
        const unsigned head[]={0x4600,0x4604,0x4608,0x4610,0x4614,0x4618,0x461c,0x4620,0x46c0,0x47c0,0x48c0,0x49c0};
        for(unsigned k=0;k<12;k++) WR(head[k],fs[k]);
        const uint32_t payload[13]={4u|3u<<4|3u<<16,0,0,0,0x3f800000,0,0,0,0x3f800000,0,0,0,0x3f800000};
        const uint32_t cases[][4]={{0x2726000e,0x27260000,0,0},{0x2726000f,0x27260000,1,1},{0x2320001f,0x23200000,3,1},{0x00000038,0,0,0}};   /* CBLEND, ABLEND, discard, blending */
        for(unsigned c=0;c<4;c++){ OpticsDraw d; const char *why=NULL; WR(0x4e04,cases[c][0]); WR(0x4e08,cases[c][1]);
            assert(optics_draw_build(&d,regs,s,0x35,payload,13,NULL,NULL,NULL,&why));
            assert(d.discard==cases[c][2] && (d.blend!=0)==(cases[c][3]!=0)); optics_draw_free(&d); }
        /* DXT1 with the alpha select ONE (Tiger's driver, SimCity 4): alpha from the block, so its transparent texels
         * stay transparent; W8Z8Y8X8 with ONE keeps it. Program: TEX LD unit 0 into temp 1, out = temp 1 (optics-dxt). */
        const uint32_t tf[]={8,0,0,0,0,0,0x400000,(1u<<15)|(1u<<6),(7u<<26)|1u,(1u<<24)|1u,(21u<<7)|(20u<<14),9u|(17u<<7)|(16u<<14)};
        for(unsigned k=0;k<12;k++) WR(head[k],tf[k]);
        WR(0x4104,1); WR(0x4480,15|15u<<11); WR(0x4540,0x200000);
        const uint32_t formats[][2]={{0xf,0x0123},{0xc,0x2105}};   /* TX_FORMAT, expected selects R,G,B,A as hex digits */
        for(unsigned c=0;c<2;c++){ OpticsDraw d; const char *why=NULL; WR(0x4e04,0); WR(0x4e08,0);
            WR(0x44c0,formats[c][0]|5u<<9|2u<<12|1u<<15|0u<<18);   /* A ONE, R Z, G Y, B X */
            if(!optics_draw_build(&d,regs,s,0x35,payload,13,NULL,NULL,NULL,&why)){ fprintf(stderr,"%s\n",why); assert(0); }
            const uint8_t *q=d.texture[0].select; assert((unsigned)(q[0]<<12|q[1]<<8|q[2]<<4|q[3])==formats[c][1]); optics_draw_free(&d); }
        #undef WR
        optics_r300_state_destroy(s);
    }
    puts("optics-draw-decode: ok (stream elements, VAP swaps, source pixel discard only while blending, DXT1 alpha)"); return 0;
}
