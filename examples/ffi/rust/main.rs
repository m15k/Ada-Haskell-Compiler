// Embedding the AHC-compiled MathLib from Rust via the generated
// safe wrappers (ahc_exports.rs).
mod ahc_exports;
use ahc_exports as ahc;

fn main() {
    ahc::init();
    println!("square(12) = {}", ahc::square(12));
    println!("fib(90) = {}", ahc::hs_fib(90));
    println!("{}", ahc::greet("Rust"));
    println!("sumTo(100) = {}", ahc::sumTo(100));
}
