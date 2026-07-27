/* Drives the MathLib.hs foreign exports through ahc_exports.h. */
#include <stdio.h>
#include <stdlib.h>
#include "ahc_exports.h"

int main(void) {
  ahc_lib_init();
  printf("square(12) = %ld\n", square(12));
  printf("fib(90) = %ld\n", hs_fib(90));
  char *g = greet("C");
  printf("%s\n", g);
  free(g);
  printf("sumTo(100) = %ld\n", sumTo(100));

  /* A runtime error inside the library reports instead of exiting,
     and the runtime keeps working afterwards. */
  long b = boom(7);
  if (*ahc_last_error())
    printf("boom(7) failed: %s\n", ahc_last_error());
  else
    printf("boom(7) = %ld (unexpected)\n", b);
  printf("square(6) = %ld (still alive)\n", square(6));
  return 0;
}
