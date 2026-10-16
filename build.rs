use std::{path::Path, process::Command};

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let output = Command::new("xcrun")
        .args(["clang", "-print-file-name=libclang_rt.osx.a"])
        .output()
        .expect("Install Apple's Command Line Tools");
    assert!(
        output.status.success(),
        "Could not locate Apple's compiler runtime"
    );
    let path = String::from_utf8(output.stdout).expect("Invalid compiler runtime path");
    let path = Path::new(path.trim());
    assert!(path.is_file(), "Apple's compiler runtime is missing");
    println!(
        "cargo:rustc-link-search=native={}",
        path.parent().expect("Compiler runtime directory").display()
    );
    println!("cargo:rustc-link-lib=static=clang_rt.osx");
    println!("cargo:rerun-if-env-changed=SDKROOT");
}
