use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail, ensure};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use fs2::FileExt;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use crate::domain::ModelId;

#[derive(Clone, Deserialize)]
struct Asset {
    name: String,
    url: String,
    size: Option<u64>,
    checksum: String,
    checksum_type: String,
}

pub fn directory(root: &Path, id: ModelId) -> PathBuf {
    root.join(match id {
        ModelId::Moonshine => "moonshine-medium-streaming-en",
        ModelId::Parakeet => "parakeet-tdt-0.6b-v2-onnx",
        ModelId::Whisper => "whisper-large-v3-turbo",
    })
}

/// Checks the complete file inventory and sizes without hashing gigabytes on the UI thread.
/// Loading and installing a model additionally verify every checksum.
pub fn installed(root: &Path, id: ModelId) -> bool {
    assets(id)
        .and_then(|files| verify_files(&directory(root, id), &files, None, false))
        .is_ok()
}

pub(crate) fn verify_cached(root: &Path, id: ModelId) -> Result<()> {
    verify_files(&directory(root, id), &assets(id)?, None, true)
}

/// Downloads to a private staging directory and atomically publishes only verified files.
/// Parakeet ONNX is a separate download from the legacy CoreML model.
pub fn download(
    root: &Path,
    id: ModelId,
    cancel: &AtomicBool,
    progress: impl Fn(f32, String),
) -> Result<()> {
    check_cancel(cancel)?;
    let files = assets(id)?;
    fs::create_dir_all(root).context("Could not create the model cache")?;
    let destination = directory(root, id);
    let name = destination
        .file_name()
        .context("Invalid model directory")?
        .to_string_lossy();
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(root.join(format!(".{name}.install.lock")))?;
    loop {
        check_cancel(cancel)?;
        match lock.try_lock_exclusive() {
            Ok(()) => break,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(error) => return Err(error.into()),
        }
    }
    progress(0.0, "Verifying cached model".to_owned());
    if verify_files(&destination, &files, Some(cancel), true).is_ok() {
        check_cancel(cancel)?;
        progress(1.0, "Model ready".to_owned());
        return Ok(());
    }
    check_cancel(cancel)?;
    let staging = tempfile::Builder::new()
        .prefix(&format!(".{name}.download-"))
        .tempdir_in(root)?;
    let client = ureq::AgentBuilder::new()
        .https_only(true)
        .timeout_connect(Duration::from_secs(10))
        .timeout_read(Duration::from_secs(10))
        .timeout_write(Duration::from_secs(10))
        .build();
    let total = files
        .iter()
        .map(|file| file.size.unwrap_or(1))
        .sum::<u64>()
        .max(1);
    let mut completed = 0_u64;
    for asset in &files {
        check_cancel(cancel)?;
        let target = staging.path().join(&asset.name);
        fs::create_dir_all(target.parent().context("Invalid model file path")?)?;
        let cached = destination.join(&asset.name);
        if verify_file(&cached, asset, Some(cancel), true).is_ok() {
            check_cancel(cancel)?;
            fs::copy(&cached, &target)?;
        } else {
            check_cancel(cancel)?;
            let mut response = client
                .get(&asset.url)
                .call()
                .with_context(|| format!("Could not download {}", asset.name))?
                .into_reader();
            let mut output = File::create(&target)?;
            let mut received = 0_u64;
            let mut buffer = [0_u8; 128 * 1024];
            let mut last_progress = Instant::now();
            loop {
                check_cancel(cancel)?;
                let count = response.read(&mut buffer)?;
                if count == 0 {
                    break;
                }
                received += count as u64;
                if let Some(size) = asset.size {
                    ensure!(received <= size, "{} exceeds its expected size", asset.name);
                }
                output.write_all(&buffer[..count])?;
                if last_progress.elapsed() >= Duration::from_millis(100) {
                    let fraction = (completed + received) as f64 / total as f64;
                    progress(
                        fraction.min(0.99) as f32,
                        format!("Downloading {}", asset.name),
                    );
                    last_progress = Instant::now();
                }
            }
            output.sync_all()?;
        }
        File::open(&target)?.sync_all()?;
        progress(
            ((completed + asset.size.unwrap_or(1)) as f64 / total as f64).min(0.99) as f32,
            format!("Verifying {}", asset.name),
        );
        verify_file(&target, asset, Some(cancel), true)?;
        completed += asset.size.unwrap_or(1);
        progress(
            (completed as f64 / total as f64).min(0.99) as f32,
            asset.name.clone(),
        );
    }
    check_cancel(cancel)?;
    publish(staging.path(), &destination)?;
    File::open(root)?.sync_all()?;
    progress(1.0, "Model ready".to_owned());
    Ok(())
}

fn check_cancel(cancel: &AtomicBool) -> Result<()> {
    ensure!(!cancel.load(Ordering::Relaxed), "Model download cancelled");
    Ok(())
}

fn verify_files(
    directory: &Path,
    assets: &[Asset],
    cancel: Option<&AtomicBool>,
    checksums: bool,
) -> Result<()> {
    for asset in assets {
        verify_file(&directory.join(&asset.name), asset, cancel, checksums)?;
    }
    Ok(())
}

fn verify_file(
    path: &Path,
    asset: &Asset,
    cancel: Option<&AtomicBool>,
    checksum: bool,
) -> Result<()> {
    let metadata = fs::symlink_metadata(path).with_context(|| format!("Missing {}", asset.name))?;
    ensure!(metadata.is_file(), "{} is not a regular file", asset.name);
    ensure!(
        metadata.len() > 0 && asset.size.is_none_or(|size| metadata.len() == size),
        "{} has the wrong size",
        asset.name
    );
    if !checksum {
        return Ok(());
    }
    let mut input = File::open(path)?;
    let mut sha = Sha256::new();
    let mut crc = 0_u32;
    let mut buffer = vec![0_u8; 1024 * 1024];
    loop {
        if let Some(cancel) = cancel {
            check_cancel(cancel)?;
        }
        let count = input.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        match asset.checksum_type.as_str() {
            "sha256" => sha.update(&buffer[..count]),
            "crc32c" => crc = crc32c::crc32c_append(crc, &buffer[..count]),
            kind => bail!("Unsupported model checksum {kind}"),
        }
    }
    let actual = match asset.checksum_type.as_str() {
        "sha256" => format!("{:x}", sha.finalize()),
        "crc32c" => STANDARD.encode(crc.to_be_bytes()),
        kind => bail!("Unsupported model checksum {kind}"),
    };
    ensure!(
        actual == asset.checksum,
        "{} failed its integrity check",
        asset.name
    );
    Ok(())
}

fn publish(staging: &Path, destination: &Path) -> Result<()> {
    if !destination.exists() {
        return fs::rename(staging, destination).context("Could not install the model");
    }
    #[cfg(target_os = "macos")]
    {
        use std::{ffi::CString, os::unix::ffi::OsStrExt};
        let from = CString::new(staging.as_os_str().as_bytes())?;
        let to = CString::new(destination.as_os_str().as_bytes())?;
        // Swapping directories keeps the previous verified installation visible until publication.
        let result = unsafe { libc::renamex_np(from.as_ptr(), to.as_ptr(), libc::RENAME_SWAP) };
        if result != 0 {
            return Err(std::io::Error::last_os_error())
                .context("Could not replace the model atomically");
        }
        Ok(())
    }
    #[cfg(target_os = "linux")]
    {
        use std::{ffi::CString, os::unix::ffi::OsStrExt};
        let from = CString::new(staging.as_os_str().as_bytes())?;
        let to = CString::new(destination.as_os_str().as_bytes())?;
        let result = unsafe {
            libc::renameat2(
                libc::AT_FDCWD,
                from.as_ptr(),
                libc::AT_FDCWD,
                to.as_ptr(),
                libc::RENAME_EXCHANGE,
            )
        };
        if result != 0 {
            return Err(std::io::Error::last_os_error())
                .context("Could not replace the model atomically");
        }
        Ok(())
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    bail!("Atomic model replacement is unsupported on this platform")
}

fn asset(name: &str, url: String, size: u64, checksum: &str) -> Asset {
    Asset {
        name: name.to_owned(),
        url,
        size: Some(size),
        checksum: checksum.to_owned(),
        checksum_type: "sha256".to_owned(),
    }
}

fn assets(id: ModelId) -> Result<Vec<Asset>> {
    let files = match id {
        ModelId::Moonshine => {
            #[derive(Deserialize)]
            struct Manifest { groups: Vec<Group> }
            #[derive(Deserialize)]
            struct Group { files: Vec<Asset> }
            let json = moonshine_rs::get_stt_dependencies("en", Some(moonshine_rs::ModelArch::MediumStreaming), false)?;
            let manifest: Manifest = serde_json::from_str(&json)?;
            manifest.groups.into_iter().next().context("Moonshine returned an empty model catalog")?.files
        }
        ModelId::Whisper => vec![asset(
            "ggml-large-v3-turbo.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin?download=true".to_owned(),
            1_624_555_275,
            "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
        )],
        ModelId::Parakeet => {
            let base = "https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/0bbb45a3365852604aef28b538a8f066f4ccaa85";
            vec![
                asset("encoder-model.int8.onnx", format!("{base}/encoder-model.int8.onnx?download=true"), 652_184_014,
                    "3e0581fda6ab843888b51e56d7ee78b6d5bc3237ec113af1f732d1d5286aa155"),
                asset("decoder_joint-model.int8.onnx", format!("{base}/decoder_joint-model.int8.onnx?download=true"), 8_998_286,
                    "a449f49acd68979d418651dd2dcb737cc0f1bf0225e009e29ee326354edbf7d3"),
                asset("vocab.txt", format!("{base}/vocab.txt?download=true"), 9_384,
                    "ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d"),
            ]
        }
    };
    ensure!(!files.is_empty(), "The model catalog is empty");
    for file in &files {
        ensure!(
            !file.name.is_empty()
                && Path::new(&file.name)
                    .components()
                    .all(|part| matches!(part, Component::Normal(_))),
            "Unsafe model file path"
        );
        let url = url::Url::parse(&file.url)?;
        ensure!(
            url.scheme() == "https"
                && matches!(
                    url.host_str(),
                    Some("download.moonshine.ai" | "huggingface.co")
                ),
            "Unsafe model download URL"
        );
        ensure!(
            matches!(file.checksum_type.as_str(), "sha256" | "crc32c") && !file.checksum.is_empty(),
            "Missing model checksum"
        );
    }
    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_corruption_even_when_the_size_matches() -> Result<()> {
        let cache = tempfile::tempdir()?;
        let path = cache.path().join("model");
        fs::write(&path, b"abc")?;
        let asset = asset(
            "model",
            String::new(),
            3,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        );
        verify_file(&path, &asset, None, true)?;
        fs::write(&path, b"abd")?;
        assert!(verify_file(&path, &asset, None, true).is_err());
        Ok(())
    }

    #[test]
    fn verifies_moonshine_crc32c_encoding() -> Result<()> {
        let cache = tempfile::tempdir()?;
        let path = cache.path().join("model");
        fs::write(&path, b"123456789")?;
        let asset = Asset {
            name: "model".into(),
            url: String::new(),
            size: Some(9),
            checksum: "4waSgw==".into(),
            checksum_type: "crc32c".into(),
        };
        verify_file(&path, &asset, None, true)
    }

    #[test]
    fn cancellation_does_not_create_an_installation() -> Result<()> {
        let cache = tempfile::tempdir()?;
        let root = cache.path().join("models");
        let result = download(&root, ModelId::Parakeet, &AtomicBool::new(true), |_, _| {
            panic!("progress after cancellation")
        });
        assert!(result.is_err());
        assert!(!root.exists());
        Ok(())
    }

    #[test]
    fn cancellation_interrupts_integrity_verification() -> Result<()> {
        let cache = tempfile::tempdir()?;
        let path = cache.path().join("model");
        fs::write(&path, b"abc")?;
        let asset = asset(
            "model",
            String::new(),
            3,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        );
        let result = verify_file(&path, &asset, Some(&AtomicBool::new(true)), true);
        assert!(result.unwrap_err().to_string().contains("cancelled"));
        Ok(())
    }

    #[test]
    fn atomically_publishes_and_replaces_a_directory() -> Result<()> {
        let cache = tempfile::tempdir()?;
        let destination = cache.path().join("installed");
        let first = tempfile::tempdir_in(cache.path())?;
        fs::write(first.path().join("model"), b"first")?;
        publish(first.path(), &destination)?;
        assert_eq!(fs::read(destination.join("model"))?, b"first");
        let second = tempfile::tempdir_in(cache.path())?;
        fs::write(second.path().join("model"), b"second")?;
        publish(second.path(), &destination)?;
        assert_eq!(fs::read(destination.join("model"))?, b"second");
        assert_eq!(fs::read(second.path().join("model"))?, b"first");
        Ok(())
    }

    #[test]
    fn parakeet_coreml_cache_is_a_separate_installation() -> Result<()> {
        let cache = tempfile::tempdir()?;
        fs::create_dir(cache.path().join("parakeet-tdt-0.6b-v2-coreml"))?;
        assert!(!installed(cache.path(), ModelId::Parakeet));
        assert_eq!(
            directory(cache.path(), ModelId::Parakeet),
            cache.path().join("parakeet-tdt-0.6b-v2-onnx")
        );
        Ok(())
    }
}
