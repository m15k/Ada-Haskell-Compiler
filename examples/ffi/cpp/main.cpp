// Embedding the AHC-compiled MathLib from C++ via the generated
// RAII wrapper (ahc_exports.hpp). Runtime errors inside the library
// arrive as std::runtime_error.
#include <cstdio>
#include "ahc_exports.hpp"

int main() {
  ahc::Lib lib;
  std::printf("square(12) = %ld\n", lib.square(12));
  std::printf("fib(90) = %ld\n", lib.hs_fib(90));
  std::printf("%s\n", lib.greet("C++").c_str());
  std::printf("sumTo(100) = %ld\n", lib.sumTo(100));
  try {
    lib.boom(7);
  } catch (const std::runtime_error &e) {
    std::printf("caught: %s\n", e.what());
  }
  std::printf("square(6) = %ld\n", lib.square(6));
  return 0;
}
