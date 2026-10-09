import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createInterface } from 'node:readline';
import { nativeMessageSchema, type AppState, type Command } from '../shared/protocol';

export class NativeBridge {
  private process: ChildProcessWithoutNullStreams | null = null;
  private pending = new Map<string, { resolve: () => void; reject: (error: Error) => void; timer: NodeJS.Timeout }>();
  private stopping = false;

  get isRunning(): boolean { return this.process !== null && !this.process.stdin.destroyed; }

  constructor(private options: {
    executable: string;
    modelDirectory: string;
    onState: (state: AppState) => void;
    onShowSettings: () => void;
    onFailure: (message: string) => void;
  }) {}

  start(): void {
    if (this.process) return;
    this.stopping = false;
    const child = spawn(this.options.executable, ['--model-directory', this.options.modelDirectory], { stdio: 'pipe' });
    this.process = child;
    const lines = createInterface({ input: child.stdout });
    lines.on('line', (line) => {
      if (this.process !== child) return;
      try {
        const message = nativeMessageSchema.parse(JSON.parse(line));
        switch (message.type) {
          case 'state': this.options.onState(message.state); break;
          case 'showSettings': this.options.onShowSettings(); break;
          case 'reply': {
            const pending = this.pending.get(message.id);
            if (!pending) break;
            this.pending.delete(message.id);
            clearTimeout(pending.timer);
            if (message.ok) pending.resolve();
            else pending.reject(new Error(message.error ?? 'The native service could not complete this action.'));
            break;
          }
        }
      } catch {
        this.fail('The native service sent an invalid response. Restart Voco.');
      }
    });
    child.stderr.on('data', (data: Buffer) => process.stderr.write(data));
    child.on('error', (error) => this.fail(`The native service could not start. ${error.message}`));
    child.on('exit', (code, signal) => {
      lines.close();
      if (this.process !== child) return;
      this.process = null;
      this.rejectPending(new Error('The native service stopped.'));
      if (!this.stopping) this.options.onFailure(`The native service stopped ${signal ?? `with code ${code}`}. Restart Voco.`);
    });
  }

  command(command: Command): Promise<void> {
    const child = this.process;
    if (!child || child.stdin.destroyed) return Promise.reject(new Error('The native service is unavailable. Restart Voco.'));
    const id = randomUUID();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('The native service did not respond. Restart Voco.'));
      }, 15_000);
      this.pending.set(id, { resolve, reject, timer });
      child.stdin.write(`${JSON.stringify({ id, command })}\n`, (error) => {
        if (!error) return;
        clearTimeout(timer);
        this.pending.delete(id);
        reject(error);
      });
    });
  }

  stop(): void {
    this.stopping = true;
    this.rejectPending(new Error('Voco is quitting.'));
    this.process?.stdin.end();
    this.process?.kill('SIGTERM');
  }

  private fail(message: string): void {
    const child = this.process;
    if (!child) return;
    this.process = null;
    child.kill('SIGTERM');
    this.rejectPending(new Error(message));
    this.options.onFailure(message);
  }

  private rejectPending(error: Error): void {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
  }
}
