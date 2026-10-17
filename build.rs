use std::{path::Path, process::Command};

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let library = out.join("libvoco_formatting.a");
    let arch = match std::env::var("CARGO_CFG_TARGET_ARCH").unwrap().as_str() {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        other => panic!("Unsupported macOS architecture: {other}"),
    };
    let status = Command::new("xcrun")
        .args([
            "swiftc",
            "-parse-as-library",
            "-emit-library",
            "-static",
            "-O",
            "-module-name",
            "VocoFormatting",
            "-target",
            &format!("{arch}-apple-macosx26.0"),
            "native/FoundationFormatting.swift",
            "-o",
        ])
        .arg(&library)
        .status()
        .expect("Install Swift 6.2 or newer and the macOS 26 SDK");
    assert!(status.success(), "Could not build FoundationModels bridge");
    let swift = Command::new("xcrun")
        .args(["--find", "swiftc"])
        .output()
        .unwrap();
    let swift = String::from_utf8(swift.stdout).unwrap();
    let runtime = Path::new(swift.trim())
        .parent()
        .unwrap()
        .join("../lib/swift/macosx");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-search=native={}", runtime.display());
    println!("cargo:rustc-link-lib=static=voco_formatting");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
    println!("cargo:rerun-if-changed=native/FoundationFormatting.swift");
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
