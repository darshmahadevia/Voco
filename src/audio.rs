use anyhow::{Context, Result, anyhow, bail, ensure};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, Sample, SampleFormat, SizedSample, Stream, StreamConfig};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU32, Ordering},
};

const OUTPUT_RATE: u32 = 16_000;
const MAX_SAMPLES: usize = OUTPUT_RATE as usize * 60 * 10;
const TAPS: usize = 64;
const PHASES: usize = 256;

pub struct Recorder {
    stream: Option<Stream>,
    capture: Arc<Mutex<Capture>>,
    meter: Arc<AtomicU32>,
}

struct Capture {
    samples: Vec<f32>,
    resampler: Resampler,
    error: Option<String>,
    at_limit: bool,
}

impl Recorder {
    pub fn start() -> Result<Self> {
        #[cfg(target_os = "macos")]
        ensure!(
            crate::platform::permissions().microphone,
            "Allow Microphone access in System Settings before recording."
        );
        let device = cpal::default_host()
            .default_input_device()
            .context("No microphone is available.")?;
        let supported = device
            .default_input_config()
            .context("Could not read the microphone format.")?;
        let config: StreamConfig = supported.clone().into();
        ensure!(config.channels > 0, "The microphone has no input channels.");
        ensure!(
            (8_000..=192_000).contains(&config.sample_rate.0),
            "The microphone sample rate is unsupported."
        );
        let mut samples = Vec::new();
        samples
            .try_reserve_exact(MAX_SAMPLES)
            .context("Could not allocate the recording buffer.")?;
        let capture = Arc::new(Mutex::new(Capture {
            samples,
            resampler: Resampler::new(config.sample_rate.0),
            error: None,
            at_limit: false,
        }));
        let meter = Arc::new(AtomicU32::new(0_f32.to_bits()));
        let stream = match supported.sample_format() {
            SampleFormat::F32 => build_stream::<f32>(&device, &config, &capture, &meter),
            SampleFormat::F64 => build_stream::<f64>(&device, &config, &capture, &meter),
            SampleFormat::I8 => build_stream::<i8>(&device, &config, &capture, &meter),
            SampleFormat::I16 => build_stream::<i16>(&device, &config, &capture, &meter),
            SampleFormat::I24 => build_stream::<cpal::I24>(&device, &config, &capture, &meter),
            SampleFormat::I32 => build_stream::<i32>(&device, &config, &capture, &meter),
            SampleFormat::I64 => build_stream::<i64>(&device, &config, &capture, &meter),
            SampleFormat::U8 => build_stream::<u8>(&device, &config, &capture, &meter),
            SampleFormat::U16 => build_stream::<u16>(&device, &config, &capture, &meter),
            SampleFormat::U32 => build_stream::<u32>(&device, &config, &capture, &meter),
            SampleFormat::U64 => build_stream::<u64>(&device, &config, &capture, &meter),
            format => bail!("The microphone sample format {format} is unsupported."),
        }?;
        stream
            .play()
            .context("Could not start microphone capture.")?;
        Ok(Self {
            stream: Some(stream),
            capture,
            meter,
        })
    }

    pub fn level(&self) -> f32 {
        f32::from_bits(self.meter.load(Ordering::Relaxed))
    }

    pub fn error(&self) -> Option<String> {
        match self.capture.lock() {
            Ok(capture) => capture.error.clone(),
            Err(_) => Some("The recording callback failed.".into()),
        }
    }

    pub fn at_limit(&self) -> bool {
        self.capture.lock().is_ok_and(|capture| capture.at_limit)
    }

    pub fn finish(mut self) -> Result<Vec<f32>> {
        let stream = self
            .stream
            .take()
            .context("The recorder has already stopped.")?;
        let stopped = stream.pause().context("Could not stop microphone capture.");
        drop(stream);
        let mut capture = self
            .capture
            .lock()
            .map_err(|_| anyhow!("The recording callback failed."))?;
        if let Some(error) = capture.error.take() {
            bail!(error);
        }
        stopped?;
        let Capture {
            samples, resampler, ..
        } = &mut *capture;
        resampler.flush(samples);
        ensure!(
            !samples.is_empty(),
            "The microphone delivered no audio. Check Microphone permission and the selected input device."
        );
        Ok(std::mem::take(samples))
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        if let Some(stream) = self.stream.take() {
            let _ = stream.pause();
            drop(stream);
        }
    }
}

fn build_stream<T>(
    device: &cpal::Device,
    config: &StreamConfig,
    capture: &Arc<Mutex<Capture>>,
    meter: &Arc<AtomicU32>,
) -> Result<Stream>
where
    T: SizedSample,
    f32: FromSample<T>,
{
    let input = Arc::clone(capture);
    let errors = Arc::clone(capture);
    let meter = Arc::clone(meter);
    let channels = usize::from(config.channels);
    device
        .build_input_stream(
            config,
            move |data: &[T], _| {
                let Ok(mut capture) = input.lock() else {
                    return;
                };
                if capture.error.is_some() || capture.at_limit {
                    return;
                }
                if !data.len().is_multiple_of(channels) {
                    capture.error =
                        Some("The microphone delivered an incomplete audio frame.".into());
                    return;
                }
                let mut energy = 0_f64;
                for frame in data.chunks_exact(channels) {
                    let mono = frame
                        .iter()
                        .map(|sample| f32::from_sample(*sample))
                        .sum::<f32>()
                        / channels as f32;
                    if !mono.is_finite() {
                        capture.error =
                            Some("The microphone delivered invalid audio samples.".into());
                        return;
                    }
                    energy += f64::from(mono) * f64::from(mono);
                    let Capture {
                        samples, resampler, ..
                    } = &mut *capture;
                    if !resampler.push(mono.clamp(-1.0, 1.0), samples, MAX_SAMPLES)
                        || samples.len() == MAX_SAMPLES
                    {
                        capture.at_limit = true;
                        meter.store(0_f32.to_bits(), Ordering::Relaxed);
                        return;
                    }
                }
                let frames = data.len() / channels;
                if frames != 0 {
                    let rms = (energy / frames as f64).sqrt() as f32;
                    meter.store((rms * 6.0).clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
                }
            },
            move |error| {
                if let Ok(mut capture) = errors.lock() {
                    capture
                        .error
                        .get_or_insert_with(|| format!("Microphone capture failed. {error}"));
                }
            },
            None,
        )
        .context("Could not open the microphone.")
}

struct Resampler {
    rate: u32,
    ring: [f32; TAPS],
    frames: u64,
    output: u64,
    kernels: Vec<[f32; TAPS]>,
}

impl Resampler {
    fn new(rate: u32) -> Self {
        let cutoff = 0.45 * (f64::from(OUTPUT_RATE) / f64::from(rate)).min(1.0);
        let kernels = (0..PHASES)
            .map(|phase| {
                let fraction = phase as f64 / PHASES as f64;
                let mut kernel = [0_f32; TAPS];
                for (tap, coefficient) in kernel.iter_mut().enumerate() {
                    let distance = tap as f64 - (TAPS / 2 - 1) as f64 - fraction;
                    let x = 2.0 * cutoff * distance;
                    let sinc = if x.abs() < 1e-12 {
                        1.0
                    } else {
                        (std::f64::consts::PI * x).sin() / (std::f64::consts::PI * x)
                    };
                    let window =
                        0.5 + 0.5 * (std::f64::consts::PI * distance / (TAPS / 2) as f64).cos();
                    *coefficient = (2.0 * cutoff * sinc * window) as f32;
                }
                let sum = kernel.iter().sum::<f32>();
                for coefficient in &mut kernel {
                    *coefficient /= sum;
                }
                kernel
            })
            .collect();
        Self {
            rate,
            ring: [0.0; TAPS],
            frames: 0,
            output: 0,
            kernels,
        }
    }

    fn push(&mut self, sample: f32, samples: &mut Vec<f32>, limit: usize) -> bool {
        if self.rate == OUTPUT_RATE {
            if samples.len() == limit {
                return false;
            }
            samples.push(sample);
            self.frames += 1;
            self.output += 1;
            return true;
        }
        self.ring[self.frames as usize % TAPS] = sample;
        self.frames += 1;
        loop {
            let numerator = self.output * u64::from(self.rate);
            let center = numerator / u64::from(OUTPUT_RATE);
            if center + (TAPS / 2) as u64 >= self.frames {
                break;
            }
            if samples.len() == limit {
                return false;
            }
            let phase = ((numerator % u64::from(OUTPUT_RATE)) * PHASES as u64
                / u64::from(OUTPUT_RATE)) as usize;
            let first = center as i64 - (TAPS / 2 - 1) as i64;
            let value = self.kernels[phase]
                .iter()
                .enumerate()
                .map(|(tap, coefficient)| {
                    let index = first + tap as i64;
                    if index < 0 {
                        0.0
                    } else {
                        self.ring[index as usize % TAPS] * coefficient
                    }
                })
                .sum::<f32>();
            samples.push(value.clamp(-1.0, 1.0));
            self.output += 1;
        }
        true
    }

    fn flush(&mut self, samples: &mut Vec<f32>) {
        if self.rate == OUTPUT_RATE {
            return;
        }
        let expected =
            (self.frames * u64::from(OUTPUT_RATE)).div_ceil(u64::from(self.rate)) as usize;
        for _ in 0..TAPS {
            if samples.len() >= expected {
                break;
            }
            if !self.push(0.0, samples, expected.min(MAX_SAMPLES)) {
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn convert(rate: u32, input: &[f32]) -> Vec<f32> {
        let mut resampler = Resampler::new(rate);
        let mut output = Vec::new();
        for sample in input {
            assert!(resampler.push(*sample, &mut output, MAX_SAMPLES));
        }
        resampler.flush(&mut output);
        output
    }

    #[test]
    fn preserves_mono_16khz_exactly() {
        let input = vec![0.0, 0.25, -0.5, 1.0, -1.0];
        assert_eq!(convert(16_000, &input), input);
    }

    #[test]
    fn preserves_duration_and_speech_band_at_device_rates() {
        for rate in [8_000, 44_100, 48_000, 96_000, 192_000] {
            let input: Vec<_> = (0..rate)
                .map(|frame| {
                    (2.0 * std::f32::consts::PI * 1_000.0 * frame as f32 / rate as f32).sin() * 0.5
                })
                .collect();
            let output = convert(rate, &input);
            assert_eq!(output.len(), 16_000, "rate {rate}");
            let error = output[100..15_900]
                .iter()
                .enumerate()
                .map(|(offset, sample)| {
                    let expected = (2.0 * std::f32::consts::PI * 1_000.0 * (offset + 100) as f32
                        / 16_000.0)
                        .sin()
                        * 0.5;
                    (sample - expected).powi(2)
                })
                .sum::<f32>()
                / 15_800.0;
            assert!(
                error.sqrt() < 0.005,
                "rate {rate}, RMS error {}",
                error.sqrt()
            );
        }
    }

    #[test]
    fn removes_frequencies_above_output_nyquist() {
        let input: Vec<_> = (0..48_000)
            .map(|frame| (2.0 * std::f32::consts::PI * 12_000.0 * frame as f32 / 48_000.0).sin())
            .collect();
        let output = convert(48_000, &input);
        let energy = output[100..15_900]
            .iter()
            .map(|sample| sample * sample)
            .sum::<f32>()
            / 15_800.0;
        assert!(energy.sqrt() < 0.01);
    }

    #[test]
    fn refuses_audio_beyond_the_buffer_limit() {
        let mut resampler = Resampler::new(16_000);
        let mut output = Vec::new();
        assert!(resampler.push(0.5, &mut output, 2));
        assert!(resampler.push(-0.5, &mut output, 2));
        assert!(!resampler.push(1.0, &mut output, 2));
        assert_eq!(output, [0.5, -0.5]);
    }
}
