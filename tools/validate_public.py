#!/usr/bin/env python3
"""Check the public sample boundary. Secret scanning is a separate CI step."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
allowed_roots = {'ios', 'content', 'config', 'tools', '.github'}
allowed_files = {'README.md', 'LICENSE', 'NOTICE.md', 'CONTRIBUTING.md', 'SECURITY.md', '.gitignore'}
for name in filter(None, paths):
    path = root / name
    assert not path.is_symlink() and path.is_file(), f'Non-regular file: {name}'
    assert name in allowed_files or Path(name).parts[0] in allowed_roots, f'Unexpected path: {name}'
    assert path.suffix.lower() not in {'.p8', '.p12', '.pem', '.key', '.mobileprovision', '.sqlite', '.ipa', '.gif'}, f'Excluded file type: {name}'
    assert not any(p in {'xcuserdata', 'DerivedData', '.env'} for p in path.parts), f'Excluded path: {name}'
    if path.suffix == '.png':
        # Initial placeholders contain only structural PNG chunks, no source metadata.
        data = path.read_bytes()
        assert data.startswith(b'\x89PNG\r\n\x1a\n'), name
        offset = 8
        while offset < len(data):
            size = int.from_bytes(data[offset:offset+4], 'big')
            assert data[offset+4:offset+8] in {b'IHDR', b'IDAT', b'IEND'}, name
            offset += 12 + size
        assert offset == len(data), name
    else:
        path.read_text()  # All other public material must be reviewable text.

config = json.loads((root / 'config/native.json').read_text())
assert config['api_url'] == 'https://api.example.invalid'
assert config['bundle_id'] == 'dev.crosscourt.sabbo.example'
assert config['team_id'] == ''
assert config['profile']['ownerID'] == 'owner'
assert config['profile']['learnerID'] == 'learner'
assert config['profile']['ownerName'] == 'Coach'
assert config['profile']['learnerName'] == 'Learner'
for path in (root / 'content').glob('*.json'):
    data = json.loads(path.read_text())
    for item in data.get('questions', data.get('sessions', [])):
        assert item['id'].startswith('demo-'), path

for path in (root / '.github/workflows').glob('*.yml'):
    text = path.read_text()
    for forbidden in ('self-hosted', 'pull_request_target', 'workflow_run:', 'secrets.', 'write-all', 'contents: write', 'id-token: write'):
        assert forbidden not in text, f'Privileged workflow feature: {path.name}'
    assert 'persist-credentials: false' in text
    for action in re.findall(r'uses:\s*(\S+)', text):
        assert re.fullmatch(r'actions/[a-z-]+@[0-9a-f]{40}', action), action
    for runner in re.findall(r'runs-on:\s*(\S+)', text):
        assert runner in {'ubuntu-latest', 'macos-15'}, runner
print('PASS public sample configuration, file boundary, PNG metadata and hosted-only CI')
