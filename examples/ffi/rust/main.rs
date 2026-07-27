// Embedding the AHC-compiled MathLib from Rust via the generated
// safe wrappers (ahc_exports.rs). Every call returns
// Result<T, String>; runtime errors inside the library are Err.
mod ahc_exports;
use ahc_exports as ahc;

fn main() {
    ahc::init();
    println!("square(12) = {}", ahc::square(12).unwrap());
    println!("fib(90) = {}", ahc::hs_fib(90).unwrap());
    println!("{}", ahc::greet("Rust").unwrap());
    println!("sumTo(100) = {}", ahc::sumTo(100).unwrap());
    match ahc::boom(7) {
        Ok(v) => println!("boom(7) = {} (unexpected)", v),
        Err(e) => println!("caught: {}", e),
    }
    println!("square(6) = {}", ahc::square(6).unwrap());
}
