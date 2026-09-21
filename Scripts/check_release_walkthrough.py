#!/usr/bin/env python3
"""Require authored, discoverable walkthrough content for every changelog feature."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
version = sys.argv[1] if len(sys.argv) > 1 else (root / 'VERSION').read_text().strip()
resources = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root / 'Sources/PanaLux/Resources'
notes = (resources / 'ReleaseNotes.md').read_text().split('\n---\n', 1)[0]
m = json.loads((resources / 'FeatureWalkthrough.json').read_text())
assert m['version'] == version, 'Update the feature walkthrough for this release version'
assert notes.startswith('# PanaLux v' + version + '\n'), 'Changelog version mismatch'
headings = re.findall(r'^- \*\*(.+?)\*\*', notes, re.M)
assert headings and set(headings) == set(m['changelogHeadings']), 'Every changelog feature must be reviewed and covered by the walkthrough manifest'
assert m['revision'] and m['steps'], 'Author a walkthrough revision and steps'
ids = set()
for s in m['steps']:
    assert s['id'] not in ids, 'Duplicate step ID'
    ids.add(s['id'])
    assert s['title'].strip() and len(s['body'].strip()) >= 60, 'Explain where and how, not just a feature name'
    assert s['target'] in ['launcher','chord','map','gestures','zoom','print','png','replay'], 'Implement a real UI spotlight for each new target'
    assert s['gesture'] in ['taps','holds','both']
    assert s['zoom'] in ['full','knobs','left','center','right','wheels']
assert {'launcher','replay'} <= {s['target'] for s in m['steps']}, 'Include discovery and replay instructions'
print(f'Walkthrough {m["revision"]}: {len(m["steps"])} authored steps cover {len(headings)} changelog features.')
