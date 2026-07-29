// Embedding the AHC Engine from C++ through the generated RAII
// wrapper. Both directions: C++ calls the Haskell exports, and the
// Haskell library calls back out to host_log below.
#include <cstdio>
#include <stdexcept>
#include <string>
#include "ahc_exports.hpp"

// The symbol Engine.hs imports - C linkage, so AHC can find it.
extern "C" void host_log(const char *msg) {
  std::printf("  [c++] %s\n", msg);
}

static const std::string TEXT =
  "the quick brown fox jumps over the lazy dog\n"
  "the dog barks and the fox runs\n";

int main() {
  ahc::Lib eng;

  std::printf("primes(12)   = %s\n", eng.primes(12).c_str());
  std::printf("factorial(30)= %s\n", eng.factorial(30).c_str());
  std::printf("evalExpr     = %ld\n", eng.evalExpr("2 * (3 + 4) - 10 / 2"));
  std::printf("wordFreq     = %s\n", eng.wordFreq(TEXT).c_str());

  std::printf("analyze:\n");
  std::printf("  -> %d words\n", eng.analyze(TEXT));

  // A parse failure arrives as an exception, not a dead process.
  try {
    eng.evalExpr("2 +");
  } catch (const std::runtime_error &e) {
    std::printf("evalExpr(bad): %s\n", e.what());
  }

  std::printf("still alive  = %ld\n", eng.evalExpr("6*7"));
  return 0;
}
