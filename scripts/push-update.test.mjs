import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const source = fileURLToPath(new URL('..', import.meta.url));

test('push updates select the current branch, reject dirty builds, and propagate failures', () => {
  const root = mkdtempSync(join(tmpdir(), 'voco-push-'));
  const env = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', PATH: `${root}/bin:${process.env.PATH}`, HOME: root };
  delete env.VOCO_SKIP_LOCAL_UPDATE;
  const run = (command, args, options = {}) => spawnSync(command, args, { cwd: root, env, encoding: 'utf8', ...options });
  const git = (...args) => {
    const result = run('git', args);
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  const script = (path, body) => { writeFileSync(path, `#!/bin/bash\n${body}\n`); chmodSync(path, 0o755); };
  try {
    mkdirSync(join(root, 'scripts'));
    mkdirSync(join(root, '.githooks'));
    mkdirSync(join(root, 'bin'));
    for (const file of ['scripts/setup-push-update.sh', '.githooks/pre-push']) copyFileSync(join(source, file), join(root, file));
    script(join(root, 'scripts/install.sh'), 'echo installed >> "$HOME/events"; exit "${INSTALL_EXIT:-0}"');
    script(join(root, 'bin/open'), 'echo opened >> "$HOME/events"');
    script(join(root, 'bin/uname'), 'echo Darwin');
    git('init', '-b', 'main');
    git('config', 'user.email', 'test@example.com');
    git('config', 'user.name', 'Test');
    git('add', '.');
    git('commit', '-m', 'Fixture');
    assert.equal(run('bash', ['scripts/setup-push-update.sh']).status, 0);
    assert.equal(git('config', '--local', 'core.hooksPath'), '.githooks');
    assert.equal(run('bash', ['scripts/setup-push-update.sh']).status, 0);
    const sha = git('rev-parse', 'HEAD');
    const zero = '0'.repeat(40);
    const input = `refs/heads/main ${sha} refs/heads/main ${zero}\n`;
    const hook = (options = {}, url = 'git@github.com:example/Voco.git', refs = input) => run('bash', ['.githooks/pre-push', 'origin', url], { input: refs, ...options });
    assert.equal(hook({ env: { ...env, VOCO_SKIP_LOCAL_UPDATE: '1' } }).status, 0);
    assert.equal(hook({}, '/tmp/local-remote.git').status, 0);
    assert.equal(hook({}, 'https://github.com/example/Voco.git', '').status, 0);
    assert.equal(hook({}, 'https://github.com/example/Voco.git', `refs/heads/other ${sha} refs/heads/other ${zero}\n`).status, 0);
    assert.equal(hook({}, 'https://github.com/example/Voco.git', `(delete) ${zero} refs/heads/main ${sha}\n`).status, 0);
    assert.equal(existsSync(join(root, 'events')), false);
    writeFileSync(join(root, 'uncommitted'), 'dirty');
    assert.match(hook().stderr, /commit or stash/);
    assert.equal(hook().status, 1);
    assert.equal(existsSync(join(root, 'events')), false);
    rmSync(join(root, 'uncommitted'));
    assert.equal(hook({ env: { ...env, INSTALL_EXIT: '9' } }).status, 9);
    assert.equal(readFileSync(join(root, 'events'), 'utf8'), 'installed\n');
    rmSync(join(root, 'events'));
    assert.equal(hook().status, 0);
    assert.equal(readFileSync(join(root, 'events'), 'utf8'), 'installed\nopened\n');
    git('config', '--local', 'core.hooksPath', 'custom-hooks');
    assert.equal(run('bash', ['scripts/setup-push-update.sh']).status, 1);
    assert.equal(git('config', '--local', 'core.hooksPath'), 'custom-hooks');
    git('config', '--local', '--unset', 'core.hooksPath');
    script(join(root, '.git/hooks/pre-commit'), 'exit 0');
    assert.equal(run('bash', ['scripts/setup-push-update.sh']).status, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
