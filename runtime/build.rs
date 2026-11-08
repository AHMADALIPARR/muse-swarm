// Under --features jetson: compile the CUDA trampoline
// (ffi/paged_attention_launcher.cu) with nvcc and link cudart.
// Without the feature this script does nothing — the host
// fallback in src/ffi.rs carries the same API.
fn main() {
    if std::env::var_os("CARGO_FEATURE_JETSON").is_some() {
        let out = std::env::var("OUT_DIR").unwrap();
        let obj = format!("{}/paged_attention_launcher.o", out);
        let status = std::process::Command::new("nvcc")
            .args([
                "-O2",
                "-arch=sm_87", // Orin NX (Ampere)
                "-c",
                "ffi/paged_attention_launcher.cu",
                "-o",
                &obj,
            ])
            .status()
            .expect("nvcc is required for --features jetson (run on the Jetson)");
        assert!(status.success(), "nvcc failed on the trampoline");
        println!("cargo:rustc-link-arg={}", obj);
        println!("cargo:rustc-link-lib=cudart");
    }
}
