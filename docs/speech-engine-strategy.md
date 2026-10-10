# Choosing a lower-cost speech path

## Recommendation

Do not try to merge Moonshine and Parakeet weights into a new checkpoint. Moonshine's official C API documents a streaming encoder and decoder with its own tokenizer assets. Parakeet uses a FastConformer encoder and TDT decoder with a different vocabulary. I infer from these incompatible architectures and asset formats that their tensors cannot be directly averaged into a usable model. A genuinely new single model would require training or distilling a student on labeled dictation or teacher-generated transcripts, followed by evaluation on held-out speech. That is an ML training project, not a product-side model combination. [Moonshine C API](https://github.com/moonshine-ai/moonshine/blob/main/core/moonshine-c-api.h) [FluidAudio model assets](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/ManualModelLoading.md) [NVIDIA Parakeet v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)

The best next candidate is **Parakeet as a single engine**, with Voco avoiding repeated full-audio inference during live updates. In the local benchmark, Parakeet had the lowest final and insertion-eligible word error rate, with much lower peak process memory than Whisper Turbo. Keep the Whisper path as a reference while evaluating this change. If live text must appear earlier than Parakeet can provide, test Moonshine as a temporary preview and run Parakeet once after release. That is a two-pass product design, not a smaller combined model, and it needs safe correction behavior before it can replace text already inserted into another app.

Before implementing that hybrid, evaluate the single-model streaming options. Voco pins FluidAudio 0.9.1, which already includes Parakeet EOU, though Voco does not use or expose it. Current FluidAudio main also documents Parakeet Unified streaming, which is not in the pinned package. Either path could avoid keeping Moonshine and Parakeet resident together.

## What the local measurements show

The October 9 benchmark ran on a 16 GB M4 MacBook Air. It scored six speakers reading LibriSpeech audiobook excerpts, totaling 406 words, plus four synthetic phrases and a silence sample.

| Model | Final WER, first / repeat | Insertion WER, first / repeat | First stable text, first / repeat | Peak process RSS max |
|---|---:|---:|---:|---:|
| Moonshine Medium Streaming English | 4.9% / 4.9% | 11.1% / 8.9% | 1.13 / 0.91 s | 1,919 MiB |
| Parakeet TDT 0.6B v2 | 0.5% / 0.5% | 1.7% / 1.7% | 2.26 / 2.25 s | 504 MiB |
| Whisper Large v3 Turbo | 0.7% / 0.7% | 4.7% / 2.5% | 3.30 / 3.30 s | 1,884 MiB |

The RSS values are standalone process measurements; they exclude the full GPU, Neural Engine, and system-memory footprint. See the [benchmark report](../benchmarks/results/2026-10-09-model-benchmark.md) and its [scope and method](model-benchmark.md).

The local complementarity check recomputed WER from the saved transcripts. Across both repetitions, a per-recording oracle that picked whichever complete transcript had fewer errors tied Parakeet at two errors out of 406 words. Moonshine had 20. The oracle had access to the reference transcript, so it cannot be used in production. It also did not test word-level merging or a trained selector. Still, these clips offer no evidence that choosing between Moonshine and Parakeet would improve on Parakeet alone. The [analysis script](../scripts/analyze-model-complementarity.py) and [result](../benchmarks/results/2026-10-09-moonshine-parakeet-complementarity.json) make this check reproducible.

Parakeet's median first stable text arrived at 2.26 seconds, compared with 1.13 seconds for Moonshine and 3.30 seconds for Whisper Turbo. Moonshine is the fastest preview engine in this small run, but its insertion-eligible text had substantially more errors. The benchmark did not measure CPU time, energy, or accelerator use. Its read-aloud English sample is too small to establish accuracy on spontaneous dictation, accents, noise, names, or numbers.

## Why a hybrid is not a fused model

Moonshine Medium Streaming is a streaming encoder-decoder model that reuses work as audio arrives. Its official benchmark guide says longer transcript-update intervals reduce some compute, and its C API describes streaming as reusing earlier calculations. Moonshine's current execution-provider guide says its shipped runtime uses CPU inference. [Moonshine streaming benchmark guide](https://github.com/moonshine-ai/moonshine/blob/main/docs/using/benchmarks.md) [Moonshine C API](https://github.com/moonshine-ai/moonshine/blob/main/core/moonshine-c-api.h) [Moonshine execution providers](https://github.com/moonshine-ai/moonshine/blob/main/docs/execution-providers.md)

Parakeet TDT v2 is a 600-million-parameter FastConformer encoder with a Token-and-Duration Transducer decoder. NVIDIA documents it as a full-attention model for batch transcription. FluidAudio's current getting-started guide also labels v2 as batch transcription. Its API accepts a full sample array and returns a transcript. [NVIDIA Parakeet v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) [FluidAudio ASR guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md)

That means the useful hybrid is sequential: Moonshine produces live text, then Parakeet transcribes once at stop. Running both repeatedly in parallel would add compute. Keeping both loaded may also raise memory use. The current benchmark does not measure concurrent RSS, so no combined memory estimate is justified.

Voco currently sends the whole Parakeet audio buffer to `AsrManager.transcribe` after each two seconds of new audio and once more on finish. The engine has no incremental Parakeet decoder state. Moonshine receives audio through its streaming API. See [ParakeetEngine.swift](../native/Sources/ParakeetEngine.swift) and [MoonshineEngine.swift](../native/Sources/MoonshineEngine.swift).

Voco now keeps recognition out of the editor until finalization. `NativeCoordinator` inserts one completed transcript, so a future preview engine could update an in-app preview without rewriting text in the destination. The obsolete stable-prefix insertion implementation has been removed. See [NativeCoordinator.swift](../native/Sources/NativeCoordinator.swift).

## How the Whisper option compares

Voco already uses Large v3 Turbo, FP16 weights, Metal acceleration, and Flash Attention. The practical next experiments are reducing repeated interim full-recording decodes, testing Q8 then Q5 quantization, and comparing the optional Core ML encoder against the current Metal path. Quantization reduces weight storage without reducing parameter count; accuracy and speed need local measurement. Core ML moves encoder work to the Neural Engine, but upstream CPU-only speedups do not predict improvements over Metal. See [the earlier Whisper review](whisper-efficiency.md) and [whisper.cpp's documentation](https://github.com/ggml-org/whisper.cpp#quantization).

Distil-Whisper research also demonstrates training a smaller student from teacher-generated transcripts, and compatible draft/teacher speculative decoding that preserves the teacher's outputs. This establishes possible techniques, not measured savings for Voco or a ready-made Moonshine/Parakeet fusion. Speculative decoding adds a draft model, so speed alone would not establish a memory or energy improvement. [Distil-Whisper paper](https://arxiv.org/abs/2311.00430)

Given Voco's English dictation goal and the current latency and process-memory baseline, I prefer optimizing the Parakeet path before investing in a new Whisper backend or a new trained model. This is a product recommendation from the available evidence, not a claim that optimized Whisper cannot win a future comparison.

## A stronger single-model option upstream

FluidAudio 0.9.1 includes Parakeet EOU, a separate 120M model with 160 and 320 ms chunk sizes. Its benchmark guide reports 4.92% WER at 320 ms and 8.29% at 160 ms on full LibriSpeech test-clean, measured on an M2. This is a useful small-model streaming candidate, but its upstream accuracy result is not comparable to Voco's six-clip Parakeet batch result. [FluidAudio 0.9.1 API](https://github.com/FluidInference/FluidAudio/blob/v0.9.1/Documentation/API.md) [FluidAudio 0.9.1 benchmark](https://github.com/FluidInference/FluidAudio/blob/v0.9.1/Documentation/Benchmarks.md)

Current FluidAudio main also reports Parakeet Unified 0.6B English, one checkpoint for batch and chunked-attention streaming. It reports 2.21% average WER for streaming and 2.15% for batch on all 2,620 LibriSpeech test-clean clips, measured on an M5 Pro. Streaming re-encodes a 7.68-second window for each 1.04-second chunk, which costs throughput. Treat these results as candidate evidence, not as a prediction for Voco's M4 benchmark. [FluidAudio Unified benchmark](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)

The [resolved dependency](../native/Package.resolved) confirms that Voco uses FluidAudio 0.9.1. Add EOU to the model comparison without upgrading FluidAudio. Upgrade only to test Unified, after checking the current package API and model license. Compare both streaming options on Voco's actual dictation set before choosing them over Parakeet TDT v2.

## Go/no-go test

First compare Parakeet-only with the same model running less often during a session while retaining one full final transcription. Measure final WER, insertion-eligible WER, first stable time, release-to-final delay, CPU time, peak process RSS, and energy on the same real dictation set. Include short phrases, long dictation, names, numbers, varied speakers, and background noise.

Only test Moonshine-preview plus Parakeet-final if users still need earlier visible words. Require final inserted text to match Parakeet-only accuracy within a predeclared margin, require preview latency to improve by a useful amount, and measure the actual concurrent or sequential memory and energy cost. Test cases where the models disagree and where the user changes focus before Parakeet finishes. Stop the hybrid experiment if it cannot correct or safely preserve already inserted text, or if the extra model cost does not buy a measurable user-facing gain.
