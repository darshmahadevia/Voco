use std::{
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
};

use anyhow::{Context, Result, ensure};
use moonshine_rs::{ModelArch, Transcriber};
use parakeet_rs::Transcriber as _;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use crate::{domain::ModelId, models};

pub struct Engine {
    runtime: Runtime,
}

enum Runtime {
    Moonshine(Transcriber),
    Parakeet(Box<parakeet_rs::ParakeetTDT>),
    Whisper(WhisperContext),
}

impl Engine {
    /// Loads a verified local model. This performs disk I/O and should run on a worker.
    pub fn load(id: ModelId, models_root: &Path) -> Result<Self> {
        models::verify_cached(models_root, id)
            .context("The speech model is missing or damaged. Download it in Settings.")?;
        let directory = models::directory(models_root, id);
        let runtime = match id {
            ModelId::Moonshine => Runtime::Moonshine(
                Transcriber::from_files(directory, ModelArch::MediumStreaming, None)
                    .context("Could not load Moonshine")?,
            ),
            ModelId::Parakeet => {
                let environment = parakeet_rs::ort::init()
                    .with_name("voco-parakeet")
                    .build()
                    .context("Could not initialize ONNX Runtime")?;
                let config = parakeet_rs::ExecutionConfig::new().with_environment(environment);
                Runtime::Parakeet(Box::new(
                    parakeet_rs::ParakeetTDT::from_pretrained(directory, Some(config))
                        .context("Could not load the Parakeet ONNX model")?,
                ))
            }
            ModelId::Whisper => {
                let mut parameters = WhisperContextParameters::default();
                parameters.use_gpu(cfg!(target_os = "macos"));
                parameters.flash_attn(true);
                Runtime::Whisper(
                    WhisperContext::new_with_params(
                        directory.join("ggml-large-v3-turbo.bin"),
                        parameters,
                    )
                    .context("Could not load Whisper")?,
                )
            }
        };
        Ok(Self { runtime })
    }

    /// Transcribes mono 16 kHz PCM. Calls are independent dictation sessions.
    pub fn transcribe(&mut self, samples: &[f32]) -> Result<String> {
        self.transcribe_cancellable(samples, &AtomicBool::new(false))
    }

    /// Moonshine checks between chunks; Whisper aborts computation through its callback.
    /// Parakeet checks before and after inference because its sessions expose no abort API.
    pub fn transcribe_cancellable(
        &mut self,
        samples: &[f32],
        cancel: &AtomicBool,
    ) -> Result<String> {
        check_cancel(cancel)?;
        ensure!(
            samples.iter().all(|sample| sample.is_finite()),
            "Audio contains non-finite samples"
        );
        if samples.is_empty() {
            return Ok(String::new());
        }
        let text = match &mut self.runtime {
            Runtime::Moonshine(transcriber) => {
                let mut stream = transcriber
                    .create_stream()
                    .context("Could not start Moonshine")?;
                for chunk in samples.chunks(16_000) {
                    check_cancel(cancel)?;
                    stream
                        .add_audio(chunk, 16_000)
                        .context("Moonshine could not process audio")?;
                }
                stream
                    .finalize()
                    .context("Moonshine transcription failed")?
                    .text()
            }
            Runtime::Parakeet(transcriber) => {
                transcriber
                    .transcribe_samples(samples.to_vec(), 16_000, 1, None)
                    .context("Parakeet transcription failed")?
                    .text
            }
            Runtime::Whisper(context) => {
                let mut state = context.create_state().context("Could not start Whisper")?;
                let mut parameters = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
                let threads = std::thread::available_parallelism()
                    .map_or(4, |n| n.get())
                    .min(8);
                parameters.set_n_threads(threads as i32);
                parameters.set_language(Some("en"));
                parameters.set_translate(false);
                parameters.set_no_context(true);
                parameters.set_no_timestamps(true);
                parameters.set_suppress_blank(true);
                parameters.set_suppress_nst(true);
                parameters.set_print_progress(false);
                parameters.set_print_realtime(false);
                parameters.set_print_timestamps(false);
                parameters.set_print_special(false);
                // full() is synchronous and finishes its callbacks before this borrowed flag expires.
                unsafe {
                    parameters.set_abort_callback(Some(whisper_cancelled));
                    parameters
                        .set_abort_callback_user_data(std::ptr::from_ref(cancel).cast_mut().cast());
                }
                // whisper.cpp requires at least 100 ms; padding retains short utterances.
                let padded;
                let audio = if samples.len() < 1_600 {
                    padded = samples
                        .iter()
                        .copied()
                        .chain(std::iter::repeat(0.0))
                        .take(1_600)
                        .collect::<Vec<_>>();
                    padded.as_slice()
                } else {
                    samples
                };
                let result = state.full(parameters, audio);
                check_cancel(cancel)?;
                result.context("Whisper transcription failed")?;
                let mut text = String::new();
                for segment in state.as_iter() {
                    text.push_str(&segment.to_str_lossy()?);
                }
                text
            }
        };
        check_cancel(cancel)?;
        Ok(text.trim().to_owned())
    }
}

fn check_cancel(cancel: &AtomicBool) -> Result<()> {
    ensure!(!cancel.load(Ordering::Relaxed), "Transcription cancelled");
    Ok(())
}

unsafe extern "C" fn whisper_cancelled(data: *mut std::ffi::c_void) -> bool {
    unsafe { &*data.cast::<AtomicBool>() }.load(Ordering::Relaxed)
}
