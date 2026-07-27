// Embedding the AHC-compiled MathLib from C++ via the generated
// RAII wrapper (ahc_exports.hpp).
#include <cstdio>
#include "ahc_exports.hpp"

int main() {
  ahc::Lib lib;
  std::printf("square(12) = %ld\n", lib.square(12));
  std::printf("fib(90) = %ld\n", lib.hs_fib(90));
  std::printf("%s\n", lib.greet("C++").c_str());
  std::printf("sumTo(100) = %ld\n", lib.sumTo(100));
  return 0;
}
