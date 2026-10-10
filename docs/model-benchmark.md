# How to benchmark Voco speech models

Use this guide to compare Voco's speech models on the same audio on your Mac. The runner measures recognition quality, live text timing, finalization delay, model load time, and peak process resident memory.

Use Python 3.10 or later. The runner uses only Python's standard library and macOS `afconvert` and `say` commands.

## Prepare the audio fixtures

The fixture set contains six human English clips from six speakers, four synthetic dictation phrases, and two seconds of silence. The human clips come from the `test` split of the `clean` configuration in [LibriSpeech on Hugging Face](https://huggingface.co/datasets/openslr/librispeech_asr). The dataset uses CC BY 4.0 and derives its recordings from LibriVox audiobooks. The fixture manifest pins a dataset revision and checks each row ID, speaker ID, and transcript before it downloads audio.

Prepare the fixtures in Voco's local cache:

```sh
python3 scripts/benchmark-models.py prepare
```

The command downloads only the six selected audio files. It does not download the full LibriSpeech corpus. It uses macOS `afconvert` to create 16 kHz mono WAV files and macOS `say` to create the synthetic clips. The default synthetic voice is Samantha. Pass `--voice NAME` to choose another installed voice.

The command writes `fixture-manifest.json` and the WAV files under `~/Library/Caches/Voco/model-benchmark`. The manifest records each audio file's SHA-256 checksum, transcript, source, and duration.

## Run the models

Install the three user-facing models through Voco setup. Make the full Whisper challenger available in a local model directory. Then build the native app and run the benchmark:

```sh
scripts/build-native.sh

NATIVE="$HOME/Library/Caches/Voco/Native/VocoNative.app/Contents/MacOS/VocoNative"
MODELS="$HOME/Library/Application Support/Voco/models"
"$NATIVE" --model moonshine --model-directory "$MODELS/moonshine-medium-streaming-en" --model-status
"$NATIVE" --model parakeet --model-directory "$MODELS/parakeet-tdt-0.6b-v2-coreml" --model-status
"$NATIVE" --model whisper --model-directory "$MODELS/whisper-large-v3-turbo" --model-status
"$NATIVE" --model whisper --whisper-variant large-v3 --model-directory "$MODELS/whisper-large-v3" --model-status

python3 scripts/benchmark-models.py run
```

The status commands verify and load each installed model before timing. They can warm the operating system's file cache and trigger first-use Core ML compilation. The benchmark therefore measures process-cold loading of an already-installed model after that preflight; it does not measure the first-ever download, setup, or Core ML compilation time. `coldStart` does not imply a cold disk cache. The runner uses the native executable and model cache paths under `~/Library/Caches/Voco` and `~/Library/Application Support/Voco/models`. Pass `--native PATH` or `--model-root PATH` if your local paths differ. Use `--model-dir KEY=PATH` more than once when model files live in different directories. Pass `--models moonshine parakeet whisper` to skip the full Whisper challenger.

The three user-facing choices are Moonshine Medium Streaming English, Parakeet TDT 0.6B v2, and Whisper Large v3 Turbo. The runner also benchmarks full Whisper Large v3 as a challenger to see whether its accuracy gain justifies its added load and response time. That challenger is not a fourth user-facing choice.

Each model processes every fixture twice in a fresh native process. The native CLI loads one model for each fixture and reuses it across warmups and scored repetitions. With the default zero warmups, the first scored pass is also the process-cold pass; with warmups enabled, the warmup consumes that pass, so scored repetitions are warm. The operating system may keep model files in its file cache, so `coldStart` does not mean a cold disk cache. The runner rotates model order by fixture to reduce order bias.

The default run uses zero warmups and two scored repetitions. Set `--warmups N` or `--repetitions N` to change those counts. Model load time is measured once before the warmups and attached to the first scored row. The runner appends newline-delimited JSON after each successful native invocation, so completed invocations remain available if a later invocation fails. It accepts a process's rows only after that process returns all requested repetitions; if repetition two fails, that invocation contributes no scored rows.

## Read the report

The run writes a raw `.jsonl` result file and a Markdown report beside it. The raw file records the exact native metrics, final and delivered transcripts, model and engine versions, fixture checksum, command, hardware and power summary (including power source, battery percent, and Low Power Mode), and timing for each process invocation. A bounded timeout is derived from audio duration and the requested warmups and repetitions; timed-out invocations are recorded as failures and excluded from scores.

The report separates the first scored and repeated passes. It shows human WER for both the final retained recognition transcript and the text eligible for live insertion after finalization, median time to first partial text, median time to first stable-buffer eligibility, release-to-final delay, model load time, peak process RSS, exact synthetic target matches for both text paths, and silence false-text counts for both. WER ignores capitalization and punctuation. Synthetic target matches require an exact formatted-text match.

Rebuild the report from a raw file with:

```sh
python3 scripts/benchmark-models.py summarize --results ~/Library/Caches/Voco/model-benchmark/results-YYYYMMDDTHHMMSSZ.jsonl
```

The benchmark does not assign a winner. Compare human WER and live response time together, then consider process RSS, number formatting, punctuation, and silence behavior. A small WER difference may not justify a slower response in Voco.

## Interpret the measurements

The six human clips cover six speakers and 406 reference words. They are read audiobook speech, not spontaneous dictation. The four macOS `say` phrases cover a short confirmation, times, dates, currency, names, and punctuation, but one synthetic voice cannot represent the range of user voices. Whisper's multilingual ability is outside this English-only benchmark. Use these results to narrow the default choice. A larger user-recorded set can confirm close results.

The Whisper weights are unquantized FP16. In this benchmark build, the native `modelVersion` label says “full precision”; that means FP16 here, not FP32.

The reference text for the human clips has no punctuation and uses uppercase letters, so punctuation quality is not part of human WER. The synthetic cases report exact formatted-text matches separately. `firstPartialMs` measures the first nonempty live result. `firstStableMs` measures when Voco's live-text buffer first makes text eligible for insertion, falling back to final commit if no partial text stabilizes during streaming; it does not include editor-write acknowledgement. `deliveredTranscript` records the stable-buffer text after finalization, while `transcript` records the final retained recognition text, including the app's ledger recovery if the final response is empty. `releaseToFinalMs` measures finalization after audio input ends. The `peakMemoryBytes` field is the process's peak resident set size; it does not measure the full GPU, ANE, or system-memory footprint. The native JSON records all timing values in milliseconds and memory in bytes.

The silence case checks whether a model emits text with no speech. A blank transcript is expected. Any nonempty transcript counts as false text.

The dataset card and license details are available on the [LibriSpeech dataset page](https://huggingface.co/datasets/openslr/librispeech_asr). The original corpus paper is [LibriSpeech: An ASR Corpus Based on Public Domain Audio Books](https://doi.org/10.1109/ICASSP.2015.7178964).
