/* Common routines

 * Based on Gramofile code, Copyright (C) 1998 J.A. Bezemer
 * Refactored by Stephen Kell (C) 2020
 
 * Licensed under the terms of the GNU General Public License.
 * ABSOLUTELY NO WARRANTY.
 * See the file `COPYING' in this directory.
 */

#include "signpr_wav.h"
#include "fmtheaders.h"
#include "signpr_general.h"
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <math.h>
#include "endian.h"

/* ----- SOURCE & READING -------------------------------------------------- */

FILE *sourcefile;
int num_read_samples_buffered = 0;
sample_t readsamplebuffer[44100];

int
openwavsource (char *filename)
/* returns 0: failure (error_window has been displayed), 1: success.
   More or less adapted from bplay.c, with stdio-patch by Axel Kohlmeyer
 */
{
  int count;
  char hd_buf[20];
  wavhead wavhd;

  if ((sourcefile = fopen (filename, "rb")) == NULL)
    {
      warnx("The source file could not be opened.");
      return 0;
    }

  count = fread (hd_buf, 1, 20, sourcefile);
  if (count < 20)
    {
      fclose (sourcefile);
      warnx("The source file could not be read, or is too short.");
      return 0;
    }

  if (strstr (hd_buf, "RIFF") == NULL)
    {
      fclose (sourcefile);
      warnx("The source file is not a .wav file, and can not be \
processed.");
      return 0;
    }

  memcpy ((void *) &wavhd, (void *) hd_buf, 20);
  count = fread (((char *) &wavhd) + 20, 1, sizeof (wavhd) - 20, sourcefile);

  if (count < sizeof (wavhd) - 20)
    {
      fclose (sourcefile);
      warnx("The source file is too short. Probably it is not \
a .wav sound file.");
      return 0;
    }

#ifdef SWAP_ENDIAN
  wavhd.format = SwapTwoBytes (wavhd.format);
  wavhd.sample_fq = SwapFourBytes (wavhd.sample_fq);
  wavhd.bit_p_spl = SwapTwoBytes (wavhd.bit_p_spl);
  wavhd.modus = SwapTwoBytes (wavhd.modus);
#endif

  if (wavhd.format != 1)
    {
      fclose (sourcefile);
      warnx ("The source file is a .wav file with unknown format, \
and can not be processed.");
      return 0;
    }

  if (wavhd.sample_fq != 44100)
    {
      fclose (sourcefile);
      warnx ("The source file is not sampled at 44100 Hz, and can \
not be processed.");
      return 0;
    }

  if (wavhd.bit_p_spl != 16)
    {
      fclose (sourcefile);
      warnx ("The source file does not have 16 bit samples, and \
can not be processed.");
      return 0;
    }

  if (wavhd.modus != 2)
    {
      fclose (sourcefile);
      warnx ("The source file is not stereo, and can not be \
processed.");
      return 0;
    }

  /* Well, everything seems to be OK */
  num_read_samples_buffered = 0;
  return 1;
}

sample_t
readsamplesource ()
{ 
  /* millions of calls to fread sure slow things down.... buffer it a little */
  static int i;

  if (i >= num_read_samples_buffered)
  {  
    num_read_samples_buffered = fread(readsamplebuffer, 4, sizeof(readsamplebuffer)/4, sourcefile); 
    i = 0; 
    if (!num_read_samples_buffered)
      {
        /* reading after end of file - this just happens when using
           pre-read buffers! */
        readsamplebuffer[0].left = 0;
        readsamplebuffer[0].right = 0;
    	return readsamplebuffer[0];
      }
  }

#ifdef SWAP_ENDIAN
  SWAPSAMPLEREF (readsamplebuffer+i);
#endif
  return readsamplebuffer[i++];
}

void
closewavsource ()
{
  fclose (sourcefile);
  num_read_samples_buffered = 0; 
}

/* And one for doubles, max size 2G */

void
qsort2double (double *a, long n)
					/* a: pointer to start of array      */
{				/* n: # elements in array            */
  long i, j;
  double x, w;

  do
    {
      i = 0;
      j = n - 1;
      x = a[j / 2];
      do
	{
	  while (a[i] < x)
	    i++;
	  while (a[j] > x)
	    j--;
	  if (i > j)
	    break;
	  w = a[i];
	  a[i] = a[j];
	  a[j] = w;
	}
      while (++i <= --j);
      if (j + 1 < n - i)
	{
	  if (j > 0)
	    qsort2double (a, j + 1);
	  a += i;
	  n -= i;
	}
      else
	{
	  if (i < n - 1)
	    qsort2double (a + i, n - i);
	  n = j + 1;
	}
    }
  while (n > 1);
}


void
secs2hms (long seconds, char *outstring)	/*  3610  ->  1:00:10  */
{
  sprintf (outstring, "%ld:%02ld:%02ld", seconds / 3600,
	   (seconds / 60) % 60,
	   seconds % 60);
}

void
fsec2hmsf (double seconds, char *outstring)
{
  double intpart = 0;
  double floatpart;
  long i;
  char helpstring[250];

  floatpart = modf (seconds, &intpart);
  i = intpart;
  secs2hms (i, outstring);

  sprintf (helpstring, "%.3f", floatpart);
  strcat (outstring, helpstring + 1);
}
