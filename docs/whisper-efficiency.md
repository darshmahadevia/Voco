# Making Voco's Whisper path lighter

## Current setup

Voco currently ships Whisper Large v3 Turbo as unquantized FP16 GGML weights. The engine uses `use_gpu = true`, Flash Attention, greedy decoding at temperature 0, English language selection, and up to eight CPU threads. The native build enables Metal and Accelerate; it does not enable whisper.cpp's optional Core ML encoder. See [WhisperEngine.swift](../native/Sources/WhisperEngine.swift) and [build-native.sh](../scripts/build-native.sh). OpenAI describes Turbo as an optimized version of Large v3 with faster transcription and some accuracy degradation ([OpenAI Whisper docs](https://github.com/openai/whisper#available-models-and-languages)). Turbo is already the less costly Whisper checkpoint in this app.

There is a larger no-model-change opportunity in how Voco calls it. Every 32,000 new samples (two seconds), Voco runs Whisper on the entire accumulated phrase; release runs the full phrase again. That repeats inference over audio already processed. Raising the partial-update interval or limiting interim decoding can reduce this repeated work while leaving the final full-phrase call, input, weights, and decoding settings intact. This should preserve the final decode's recognition behavior; it does delay live text, so compare both live timing and final accuracy. The current benchmark measures no CPU time, energy, or GPU utilization.

## Quantization

whisper.cpp can quantize GGML weights to 4-, 5-, or 8-bit formats. Its documentation says quantized files use less disk and memory, and may run more efficiently depending on hardware ([whisper.cpp quantization docs](https://github.com/ggml-org/whisper.cpp#quantization)). Quantization keeps the model architecture and parameter count; it stores weights at lower precision. It does not promise unchanged recognition accuracy or faster inference. On this Apple Silicon path, compare Q8 first, then Q5 if memory is still a problem. Keep FP16 as the accuracy baseline and measure the same clips plus real user dictation before choosing a default.

## Smaller or specialized models

Voco's October 9 M4 benchmark already compared Turbo with full Large v3: on six read-audiobook clips (406 reference words), Turbo made 3 word errors (0.7%) and full Large made 2 (0.5%). Maximum process RSS was 1,884 MiB for Turbo and 3,945 MiB for Large; repeated-pass median finalization was 1,410 ms and 4,289 ms respectively. This small English sample supports keeping Turbo as the Whisper option; it cannot establish equal accuracy across accents, noise, languages, or spontaneous dictation. RSS also excludes the full GPU/ANE/system-memory footprint ([local report](../benchmarks/results/2026-10-09-model-benchmark.md), [benchmark scope](model-benchmark.md)).

Distil-Whisper is a separate distilled model family. Its maintainers report Distil-Large-v3 at 756M parameters and relative latency 6.3x faster than Large v3 in their evaluation, with English-only recognition. Its model card provides whisper.cpp integration instructions, while the current Voco installer only provides Turbo and Large v3. Treat it as an integration experiment: confirm a compatible GGML checkpoint, then benchmark on Voco's Mac and dictation fixtures. Those upstream speed and WER figures are not predictions for this app, and compare against full Large v3 rather than Voco's Turbo ([Distil-Large-v3 model card](https://huggingface.co/distil-whisper/distil-large-v3)).

## CPU use versus total resource use

Voco already enables Metal, which whisper.cpp documents as its Apple Silicon GPU path. Its optional Core ML support runs the encoder on Apple's Neural Engine and the upstream README reports more than 3x speed over CPU-only execution; it requires a separately generated Core ML encoder and a Core ML-enabled build. That CPU-only comparison does not show a gain over Voco's existing Metal path, nor does it prove lower total energy or memory on an M4. Core ML's first run also compiles the model and can take longer ([whisper.cpp Apple Silicon and Core ML docs](https://github.com/ggml-org/whisper.cpp#core-ml-support)).

The eight-thread cap is a tunable CPU-concurrency limit, not a guarantee of lower total work. Benchmark several caps (for example 2, 4, and 8) against wall time and CPU usage; fewer threads may lower peak CPU use while making inference slower. On an Apple Silicon system, CPU load alone misses Metal or Neural Engine work. Voco's current peak-RSS metric cannot measure those other resources.

## Suggested order

First reduce redundant interim full-phrase decodes while retaining the same final decode. Then benchmark the current Turbo weights in Q8 and Q5 if memory or disk footprint remains a concern. Profile thread caps and Core ML only after collecting CPU, GPU/ANE, and wall-time measurements. Consider Distil only if an appropriate compatible checkpoint is available and English-only scope is acceptable. No option should be described as preserving accuracy until tested against a larger, representative dictation set.
