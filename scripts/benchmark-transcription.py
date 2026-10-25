#!/usr/bin/env python3
"""Measure release CLI file transcription including model verification and loading."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import re
import statistics
import subprocess
import time
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--audio', type=Path, required=True)
parser.add_argument('--expected', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--runs', type=int, default=5)
parser.add_argument('--profile', action='store_true')
parser.add_argument('--models', nargs='+', default=['parakeet', 'whisper'])
args = parser.parse_args()
assert args.runs >= 5
root = Path(__file__).resolve().parents[1]
binary = root / 'target/release/voco'
args.output.mkdir(parents=True, exist_ok=False)
with wave.open(str(args.audio)) as audio:
    assert audio.getnchannels() == 1 and audio.getframerate() == 16000
    duration = audio.getnframes() / audio.getframerate()
expected = args.expected.read_text().strip()
reference = re.findall(r"[a-z0-9]+", expected.lower())
report = {
    'method': 'Fresh release CLI per trial. Wall time includes process startup, WAV decoding, model checksum verification, model loading, inference, and transcript output. File caches may be warm. No microphone, UI, cleanup mode, or insertion timing.',
    'audio_kind': 'Synthetic speech generated with macOS say, Samantha voice, 165 words per minute.',
    'host': platform.platform(),
    'hardware': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
    'memory_bytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
    'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'audio_sha256': hashlib.sha256(args.audio.read_bytes()).hexdigest(),
    'audio_seconds': duration,
    'expected_text': expected,
    'diagnostics': json.loads(subprocess.check_output([str(binary), '--diagnostics'], text=True)),
    'trials': [],
}
for trial in range(args.runs):
    order = args.models if trial % 2 == 0 else list(reversed(args.models))
    for model in order:
        load = subprocess.check_output(['uptime'], text=True).strip()
        started = time.monotonic()
        run = subprocess.run(['/usr/bin/time', '-l', str(binary), '--transcribe', model, str(args.audio.resolve())], capture_output=True, text=True, timeout=180)
        elapsed = time.monotonic() - started
        (args.output / f'{trial + 1}-{model}.stderr.txt').write_text(run.stderr)
        hypothesis = re.findall(r"[a-z0-9]+", run.stdout.lower())
        distance = list(range(len(hypothesis) + 1))
        for index, word in enumerate(reference, 1):
            previous = distance
            distance = [index]
            for offset, actual in enumerate(hypothesis, 1):
                distance.append(min(distance[-1] + 1, previous[offset] + 1, previous[offset - 1] + (word != actual)))
        memory = re.search(r'(\d+)\s+maximum resident set size', run.stderr)
        record = {'trial': trial + 1, 'model': model, 'returncode': run.returncode, 'wall_seconds': elapsed, 'audio_to_wall_ratio': duration / elapsed, 'transcript': run.stdout.strip(), 'word_edits': distance[-1], 'reference_words': len(reference), 'fixture_word_error_rate': distance[-1] / len(reference), 'max_rss_bytes': int(memory[1]) if memory else None, 'load': load}
        report['trials'].append(record)
        (args.output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        assert run.returncode == 0 and hypothesis and memory, record
        print(f'{model} trial {trial + 1}: {elapsed:.3f}s, {distance[-1]}/{len(reference)} word edits', flush=True)
report['summary'] = {}
for model in args.models:
    rows = [row for row in report['trials'] if row['model'] == model]
    report['summary'][model] = {key: {'median': statistics.median(row[key] for row in rows), 'range': [min(row[key] for row in rows), max(row[key] for row in rows)]} for key in ['wall_seconds', 'audio_to_wall_ratio', 'max_rss_bytes', 'fixture_word_error_rate']}
report['successful_trials'] = len(report['trials'])
report['failed_trials'] = sum(row['returncode'] != 0 for row in report['trials'])
(args.output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
if args.profile:
    with (args.output / 'profile.stderr.txt').open('w') as error_log, (args.output / 'profile.transcript.txt').open('w') as output_log:
        child = subprocess.Popen([str(binary), '--transcribe', 'whisper', str(args.audio.resolve())], stdout=output_log, stderr=error_log)
        profile = subprocess.run(['sample', str(child.pid), '1', '-file', str(args.output / 'whisper-profile.txt')], capture_output=True, text=True, timeout=15)
        result = child.wait(timeout=180)
        (args.output / 'profile-status.json').write_text(json.dumps({'excluded_from_timing_summary': True, 'engine_exit_code': result, 'sampler_exit_code': profile.returncode, 'sampler_stderr': profile.stderr}, indent=2) + '\n')
print(json.dumps(report['summary'], indent=2))
