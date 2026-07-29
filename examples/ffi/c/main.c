/* Embedding the AHC Engine from plain C.
 *
 * Two directions in one program: C calls the Haskell exports through
 * ahc_exports.h, and the Haskell library calls back out to host_log
 * below - which C defines and the linker resolves. */
#include <stdio.h>
#include <stdlib.h>
#include "ahc_exports.h"

/* The symbol Engine.hs imports. */
void host_log(const char *msg) {
  printf("  [c] %s\n", msg);
}

static const char *TEXT =
  "the quick brown fox jumps over the lazy dog\n"
  "the dog barks and the fox runs\n";

int main(void) {
  ahc_lib_init();

  char *p = primes(12);
  printf("primes(12)   = %s\n", p);
  free(p);

  char *f = factorial(30);
  printf("factorial(30)= %s\n", f);
  free(f);

  printf("evalExpr     = %ld\n", evalExpr("2 * (3 + 4) - 10 / 2"));

  char *w = wordFreq(TEXT);
  printf("wordFreq     = %s\n", w);
  free(w);

  printf("analyze:\n");
  printf("  -> %d words\n", analyze(TEXT));

  /* A parse failure crosses the boundary as an error, not an exit. */
  long bad = evalExpr("2 +");
  if (*ahc_last_error())
    printf("evalExpr(bad): %s\n", ahc_last_error());
  else
    printf("evalExpr(bad) = %ld (unexpected)\n", bad);

  printf("still alive  = %ld\n", evalExpr("6*7"));
  return 0;
}
