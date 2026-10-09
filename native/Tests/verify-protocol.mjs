import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const executable = process.argv[2];
assert.ok(executable, 'native helper executable path is required');

const temporaryDirectory = await mkdtemp(join(tmpdir(), 'voco-native-protocol-'));
const processHandle = spawn(executable, ['--model-directory', join(temporaryDirectory, 'models')], {
  env: { ...process.env, VOCO_SKIP_PREFERENCE_MIGRATION: '1' },
  stdio: ['pipe', 'pipe', 'pipe'],
});

let stdout = '';
let stderr = '';
processHandle.stdout.setEncoding('utf8').on('data', (chunk) => { stdout += chunk; });
processHandle.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });

const exited = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => {
    processHandle.kill('SIGTERM');
    reject(new Error('native protocol process did not exit after stdin closed'));
  }, 10000);
  processHandle.once('error', (error) => {
    clearTimeout(timeout);
    reject(error);
  });
  processHandle.once('exit', (code, signal) => {
    clearTimeout(timeout);
    if (code === 0) resolve();
    else reject(new Error(`native helper exited ${code ?? signal}: ${stderr}`));
  });
});

processHandle.stdin.write(`${JSON.stringify({ id: 'refresh-1', command: { kind: 'refresh' } })}\n`);
processHandle.stdin.write(`${JSON.stringify({
  id: 'invalid-preferences-1',
  command: { kind: 'setPreferences', preferences: { keepLastTranscript: 'yes' } },
})}\n`);
processHandle.stdin.end();

try {
  await exited;
  const messages = stdout.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
  assert.ok(messages.length >= 4, 'helper emitted startup states and command replies');

  const replies = messages.filter((message) => message.type === 'reply');
  assert.deepEqual(replies.map((reply) => reply.id).sort(), ['invalid-preferences-1', 'refresh-1']);
  assert.equal(replies.find((reply) => reply.id === 'refresh-1').ok, true);
  const rejected = replies.find((reply) => reply.id === 'invalid-preferences-1');
  assert.equal(rejected.ok, false);
  assert.equal(typeof rejected.error, 'string');

  const states = messages.filter((message) => message.type === 'state').map((message) => message.state);
  assert.ok(states.length > 0, 'helper emitted state updates');
  for (const state of states) {
    assert.deepEqual(Object.keys(state).sort(), ['audioLevel', 'lastTranscript', 'model', 'permissions', 'preferences', 'session']);
    assert.equal(state.audioLevel, 0, 'the idle helper starts with a silent waveform');
    assert.equal(typeof state.lastTranscript, 'string');
    assert.ok(['missing', 'downloading', 'loading', 'ready', 'error'].includes(state.model.kind));
    assert.ok(['idle', 'starting', 'listening', 'finishing', 'recovery'].includes(state.session.kind));
    assert.deepEqual(Object.keys(state.permissions).sort(), ['accessibility', 'microphone', 'shortcut']);
    assert.ok(['required', 'denied', 'granted'].includes(state.permissions.microphone));
    assert.equal(typeof state.permissions.accessibility, 'boolean');
    assert.equal(typeof state.permissions.shortcut, 'boolean');
    assert.deepEqual(Object.keys(state.preferences).sort(), ['keepLastTranscript']);
    assert.equal(typeof state.preferences.keepLastTranscript, 'boolean');
  }
  assert.equal(states.at(-1).lastTranscript, '', 'transcripts are not restored from preferences');
  console.log('PASS — native JSONL protocol');
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
