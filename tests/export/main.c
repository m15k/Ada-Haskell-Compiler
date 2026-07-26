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
  return 0;
}
