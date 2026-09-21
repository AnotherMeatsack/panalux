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
    assert s['target'] in ['guide','help','settings','map','inspector'], 'Implement a real UI spotlight for each new target'
    assert s['kind'] in ['new','updated'], 'Say whether the item is new or updated'
    assert re.fullmatch(r'\d+(\.\d+)*', s['since']), 'since must be a version'
    assert tuple(map(int, s['since'].split('.'))) <= tuple(map(int, version.split('.'))), 'since cannot be after this release'
assert any(s['since'] == version for s in m['steps']), 'Author at least one item that is new in this version'
print(f'Walkthrough {m["revision"]}: {len(m["steps"])} authored steps cover {len(headings)} changelog features.')
