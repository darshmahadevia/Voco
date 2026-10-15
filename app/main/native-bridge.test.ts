import { mkdtemp, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, expect, it } from 'vitest';
import { NativeBridge } from './native-bridge';
import type { AppState } from '../shared/protocol';
import { initialState } from '../shared/state';

const cleanups: (() => Promise<void>)[] = [];
afterEach(async () => { for (const cleanup of cleanups.splice(0)) await cleanup(); });

async function fixture(source: string): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), 'voco-bridge-'));
  cleanups.push(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'native-fixture');
  await writeFile(path, `#!${process.execPath}\n${source}`);
  await chmod(path, 0o700);
  return path;
}

it('receives state and correlates native replies over real process pipes', async () => {
  const executable = await fixture(`
const readline = require('node:readline');
process.stdout.write(JSON.stringify({type:'state',state:${JSON.stringify(initialState)}})+'\\n');
readline.createInterface({input:process.stdin}).on('line', line => {
  const {id,command} = JSON.parse(line);
  process.stdout.write(JSON.stringify({type:'reply',id,ok:command.kind!=='copyLast',error:'No saved transcript.'})+'\\n');
});
`);
  let resolveState: (state: AppState) => void = () => {};
  const firstState = new Promise<AppState>((resolve) => { resolveState = resolve; });
  const bridge = new NativeBridge({ executable, modelDirectory: '/tmp/model fixture', onState: resolveState, onShowSettings: () => {}, onFailure: () => {} });
  cleanups.push(async () => bridge.stop());
  bridge.start();
  expect(await firstState).toEqual(initialState);
  expect(bridge.isRunning).toBe(true);
  await expect(bridge.command({ kind: 'refresh' })).resolves.toBeUndefined();
  await expect(bridge.command({ kind: 'copyLast' })).rejects.toThrow('No saved transcript.');
});

it('reports unexpected native process exits and rejects outstanding commands', async () => {
  const executable = await fixture(`
require('node:readline').createInterface({input:process.stdin}).on('line', () => process.exit(7));
`);
  let reportFailure: (message: string) => void = () => {};
  const failure = new Promise<string>((resolve) => { reportFailure = resolve; });
  const bridge = new NativeBridge({ executable, modelDirectory: '/tmp/models', onState: () => {}, onShowSettings: () => {}, onFailure: reportFailure });
  cleanups.push(async () => bridge.stop());
  bridge.start();
  await expect(bridge.command({ kind: 'refresh' })).rejects.toThrow('The native service stopped.');
  expect(await failure).toBe('The native service stopped with code 7. Restart Voco.');
  expect(bridge.isRunning).toBe(false);
});

it('stops a helper after invalid output and ignores later state', async () => {
  const executable = await fixture(`
require('node:readline').createInterface({input:process.stdin}).on('line', () => {
  process.stdout.write('invalid JSON\\n');
  process.stdout.write(JSON.stringify({type:'state',state:${JSON.stringify(initialState)}})+'\\n');
});
`);
  const states: AppState[] = [];
  const failures: string[] = [];
  const bridge = new NativeBridge({ executable, modelDirectory: '/tmp/models', onState: (state) => states.push(state), onShowSettings: () => {}, onFailure: (message) => failures.push(message) });
  cleanups.push(async () => bridge.stop());
  bridge.start();
  await expect(bridge.command({ kind: 'refresh' })).rejects.toThrow('invalid response');
  await new Promise((resolve) => setTimeout(resolve, 50));
  expect(bridge.isRunning).toBe(false);
  expect(states).toEqual([]);
  expect(failures).toEqual(['The native service sent an invalid response. Restart Voco.']);
});


it('fails an unresponsive helper once and rejects every pending command', async () => {
  const executable = await fixture("process.stdin.resume();");
  const failures: string[] = [];
  const bridge = new NativeBridge({ executable, modelDirectory: '/tmp/models', commandTimeoutMs: 100,
    onState: () => {}, onShowSettings: () => {}, onFailure: message => failures.push(message) });
  cleanups.push(async () => bridge.stop());
  bridge.start();
  const replies = await Promise.allSettled([bridge.command({ kind: 'refresh' }), bridge.command({ kind: 'copyLast' })]);
  expect(replies.map(reply => reply.status)).toEqual(['rejected', 'rejected']);
  expect(failures).toEqual(['The native service did not respond. Restart Voco.']);
  expect(bridge.isRunning).toBe(false);
  await expect(bridge.command({ kind: 'refresh' })).rejects.toThrow('unavailable');
});
