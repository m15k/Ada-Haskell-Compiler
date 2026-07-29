// Embedding the AHC Engine from Rust through the generated safe
// wrappers. Both directions: Rust calls the Haskell exports (every
// call a Result), and the Haskell library calls back out to the
// host_log below.
mod ahc_exports;
use ahc_exports as eng;
use std::ffi::CStr;
use std::os::raw::c_char;

// The symbol Engine.hs imports.
#[no_mangle]
pub extern "C" fn host_log(msg: *const c_char) {
    let s = unsafe { CStr::from_ptr(msg) }.to_string_lossy();
    println!("  [rust] {}", s);
}

const TEXT: &str = "the quick brown fox jumps over the lazy dog\n\
                    the dog barks and the fox runs\n";

fn main() {
    eng::init();

    println!("primes(12)   = {}", eng::primes(12).unwrap());
    println!("factorial(30)= {}", eng::factorial(30).unwrap());
    println!("evalExpr     = {}", eng::evalExpr("2 * (3 + 4) - 10 / 2").unwrap());
    println!("wordFreq     = {}", eng::wordFreq(TEXT).unwrap());

    println!("analyze:");
    println!("  -> {} words", eng::analyze(TEXT).unwrap());

    // A parse failure arrives as Err, not a dead process.
    match eng::evalExpr("2 +") {
        Ok(v) => println!("evalExpr(bad) = {} (unexpected)", v),
        Err(e) => println!("evalExpr(bad): {}", e),
    }

    println!("still alive  = {}", eng::evalExpr("6*7").unwrap());
}
