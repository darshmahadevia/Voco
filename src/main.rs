use anyhow::{Context, Result, bail};
use std::{
    fs::{self, File, OpenOptions},
    path::{Path, PathBuf},
    sync::atomic::AtomicBool,
};
use voco::{
    domain::{ModelId, OutputMode},
    models, platform,
    speech::Engine,
    storage,
};

fn model(value: &str) -> Result<ModelId> {
    match value {
        "moonshine" => Ok(ModelId::Moonshine),
        "parakeet" => Ok(ModelId::Parakeet),
        "whisper" => Ok(ModelId::Whisper),
        _ => bail!("Unknown model {value}. Use moonshine, parakeet, or whisper."),
    }
}

fn read_wave(path: &Path) -> Result<Vec<f32>> {
    let mut reader = hound::WavReader::open(path).context("Could not open WAV audio")?;
    let spec = reader.spec();
    if spec.sample_rate != 16_000 || spec.channels != 1 {
        bail!("Audio must be mono 16 kHz WAV.");
    }
    match spec.sample_format {
        hound::SampleFormat::Float => reader
            .samples::<f32>()
            .collect::<std::result::Result<Vec<_>, _>>()
            .context("Invalid float WAV"),
        hound::SampleFormat::Int => {
            let scale = 2.0_f32.powi(i32::from(spec.bits_per_sample) - 1);
            reader
                .samples::<i32>()
                .map(|sample| sample.map(|value| value as f32 / scale))
                .collect::<std::result::Result<Vec<_>, _>>()
                .context("Invalid PCM WAV")
        }
    }
}

fn lock(root: &Path) -> Result<Option<File>> {
    use fs2::FileExt;
    fs::create_dir_all(root)?;
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(root.join("voco.lock"))?;
    match file.try_lock_exclusive() {
        Ok(()) => Ok(Some(file)),
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
        Err(error) => Err(error).context("Could not lock the Voco profile"),
    }
}

fn run() -> Result<()> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let root = storage::app_directory()?;
    let models_root = root.join("models");
    match args.first().map(String::as_str) {
        Some("--help" | "-h") => {
            println!(
                "Voco {}\n\nUsage: voco [--show]\n       voco --diagnostics\n       voco --verify-insertion\n       voco --download MODEL\n       voco --transcribe MODEL AUDIO.wav\n       voco --cleanup MODE TEXT\n       voco --verify-ui DIRECTORY\n\nModels: moonshine, parakeet, whisper\nModes: fast, balanced, accurate\nAudio: mono 16 kHz WAV.\nVOCO_DATA_DIR selects an isolated profile.",
                env!("CARGO_PKG_VERSION")
            );
            return Ok(());
        }
        Some("--version") => {
            println!("Voco {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        Some("--verify-insertion") => {
            println!(
                "{}",
                serde_json::to_string_pretty(&platform::verify_insertion()?)?
            );
            return Ok(());
        }
        Some("--diagnostics") => {
            let permissions = platform::permissions();
            let installed = ModelId::ALL.map(|id| serde_json::json!({ "model": format!("{id:?}").to_lowercase(), "installed": models::installed(&models_root, id), "directory": models::directory(&models_root, id) }));
            println!(
                "{}",
                serde_json::to_string_pretty(
                    &serde_json::json!({"version": env!("CARGO_PKG_VERSION"), "runtime": "rust", "profile": root, "microphone": permissions.microphone, "accessibility": permissions.accessibility, "models": installed})
                )?
            );
            return Ok(());
        }
        Some("--download") if args.len() == 2 => {
            let id = model(&args[1])?;
            models::download(
                &models_root,
                id,
                &AtomicBool::new(false),
                |progress, file| eprintln!("{:.0}% {file}", progress * 100.0),
            )?;
            println!("{} is installed.", id.label());
            return Ok(());
        }
        Some("--transcribe") if args.len() == 3 => {
            let samples = read_wave(Path::new(&args[2]))?;
            let mut engine = Engine::load(model(&args[1])?, &models_root)?;
            println!("{}", engine.transcribe(&samples)?);
            return Ok(());
        }
        Some("--cleanup") if args.len() == 3 => {
            let mode = match args[1].as_str() {
                "fast" => OutputMode::Fast,
                "balanced" => OutputMode::Balanced,
                "accurate" => OutputMode::Accurate,
                _ => bail!("Unknown output mode"),
            };
            let (text, notice) = voco::cleanup::polish(&args[2], mode);
            println!("{text}");
            if !notice.is_empty() {
                eprintln!("{notice}");
            }
            return Ok(());
        }
        Some("--show") if args.len() == 1 => {}
        Some("--verify-ui") if args.len() == 2 => {}
        None => {}
        _ => bail!("Invalid arguments. Run voco --help."),
    }
    let Some(_lock) = lock(&root)? else {
        if args.first().is_some_and(|arg| arg == "--show") {
            fs::write(root.join("show-dashboard"), b"show")?;
        }
        return Ok(());
    };
    let verification = if args.first().is_some_and(|arg| arg == "--verify-ui") {
        let directory = PathBuf::from(&args[1]);
        fs::create_dir_all(&directory)?;
        Some(directory)
    } else {
        None
    };
    let show = args.first().is_some_and(|arg| arg == "--show") || verification.is_some();
    let image = image::load_from_memory(include_bytes!("../Resources/Brand/voco-app.png"))
        .ok()
        .map(|image| {
            let rgba = image.into_rgba8();
            let (width, height) = rgba.dimensions();
            eframe::egui::IconData {
                rgba: rgba.into_raw(),
                width,
                height,
            }
        });
    let mut viewport = eframe::egui::ViewportBuilder::default()
        .with_title("Voco")
        .with_inner_size([960.0, 720.0])
        .with_min_inner_size([720.0, 520.0])
        .with_max_inner_size([960.0, 720.0])
        .with_maximize_button(false)
        .with_visible(show)
        .with_app_id("org.vocoapp.Voco");
    if let Some(icon) = image {
        viewport = viewport.with_icon(icon);
    }
    let options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };
    eframe::run_native(
        "Voco",
        options,
        Box::new(move |cc| {
            Ok(Box::new(voco::ui::VocoApp::new(
                cc,
                root,
                show,
                verification,
            )?))
        }),
    )
    .map_err(|error| anyhow::anyhow!("Could not open Voco. {error}"))?;
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("Voco: {error:#}");
        std::process::exit(1);
    }
}
