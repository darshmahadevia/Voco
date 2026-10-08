#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$project_dir" <<'PY'
import os
import pathlib
import plistlib
import shlex
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='voco-install-check-') as scratch:
    root = pathlib.Path(scratch)
    app = root / 'Applications/Voco.app'
    bundle = root / 'bundle/Bundle/Voco.app'
    (root / 'scripts').mkdir()
    (root / 'Resources').mkdir()
    (root / 'bin').mkdir()
    (root / 'Resources/Info.plist').write_bytes((source / 'Resources/Info.plist').read_bytes())
    own_id = plistlib.loads((source / 'Resources/Info.plist').read_bytes())['CFBundleIdentifier']
    installer = (source / 'scripts/install.sh').read_text()
    installer = installer.replace('app_dir="$HOME/Applications/Voco.app"', 'app_dir=' + shlex.quote(str(app)))
    installer = installer.replace('mkdir -p "$HOME/Applications"', 'mkdir -p ' + shlex.quote(str(app.parent)))
    installer = installer.replace('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', 'lsregister')
    (root / 'scripts/install.sh').write_text(installer)
    (root / 'scripts/build.sh').write_text('#!/bin/bash\nexit 0\n')
    (root / 'scripts/build.sh').chmod(0o755)
    commands = {
        'codesign': '''#!/bin/bash
if test "$1" = -dv; then
    printf 'CDHash=%s\\n' "$(cat "${@: -1}/.hash")" >&2
elif test "$1" = -d; then
    printf '# designated => %s\\n' "$(cat "${@: -1}/.requirement")" >&2
fi
''',
        'tccutil': '#!/bin/bash\nprintf "%s\\n" "$*" >> "$VOCO_RESET_LOG"\n',
        'pgrep': '#!/bin/bash\nexit 1\n',
        'lsregister': '#!/bin/bash\nprintf "%s\\n" "$*" >> "$VOCO_REGISTER_LOG"\n',
    }
    for name, script in commands.items():
        target = root / 'bin' / name
        target.write_text(script)
        target.chmod(0o755)
    resets = root / 'resets'
    registrations = root / 'registrations'
    env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
               VOCO_BUILD_DIR=str(root / 'bundle'), VOCO_RESET_LOG=str(resets),
               VOCO_REGISTER_LOG=str(registrations))

    def write_app(path, identity, requirement, digest, executable='Voco'):
        (path / 'Contents').mkdir(parents=True, exist_ok=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': identity, 'CFBundleExecutable': executable,
        }))
        (path / '.hash').write_text(digest)
        (path / '.requirement').write_text(requirement)

    def run(label, expected_resets, expected_status=0):
        resets.write_text('')
        registrations.write_text('')
        result = subprocess.run(['bash', str(root / 'scripts/install.sh')], env=env, capture_output=True, text=True)
        assert result.returncode == expected_status, (label, result.stdout, result.stderr)
        assert resets.read_text().splitlines() == expected_resets, (label, resets.read_text())
        assert registrations.read_text().splitlines() == ([f'-f {app}'] if expected_status == 0 else []), label
        print(label + ': PASS')

    write_app(bundle, own_id, 'new requirement', 'new hash')
    own_resets = [f'reset ListenEvent {own_id}', f'reset Microphone {own_id}', f'reset Accessibility {own_id}']
    run('First or deleted-app reinstall clears only Voco stale grants', own_resets)
    write_app(app, 'org.utterapp.Utter', 'old requirement', 'old hash')
    run('Legacy Voco migration preserves Utter permissions', own_resets)
    run('Identical reinstall preserves grants', [])
    write_app(app, own_id, 'new requirement', 'different hash')
    run('Stable signing requirement preserves grants across binary changes', [])
    write_app(app, own_id, 'old requirement', 'old hash')
    run('Changed requirement resets only Voco', own_resets)
    write_app(app, 'org.other.App', 'other requirement', 'other hash')
    run('Unrelated destination app is rejected', [], 1)
    assert plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier'] == 'org.other.App'
    write_app(app, 'org.utterapp.Utter', 'utter requirement', 'utter hash', 'Utter')
    run('Utter executable at the destination is rejected', [], 1)
PY
