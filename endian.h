/*  Header file for endian.c          */
/*  Joshua Weage   gte855f@prism.gatech.edu  */

#ifndef _GETBIG
#define _GETBIG 1

extern u_short SwapTwoBytes (u_short);
extern u_long SwapFourBytes (u_long);
extern sample_t SwapSample (sample_t);

/* macro to swap endianness of values in a sample_t with */
/* a few 32-bit operations -- very fast                  */
#define SWAPSAMPLEREF(s) *((uint32_t *)(s)) = \
	((*((uint32_t *)(s)) & 0xff00ff00) >> 8) | \
	((*((uint32_t *)(s)) & 0x00ff00ff) << 8)

#endif
