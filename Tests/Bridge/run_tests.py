"""Run bridge tests without launching Lightroom: python3 Tests/Bridge/run_tests.py /path/to/lua"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
lua = sys.argv[1] if len(sys.argv) > 1 else 'lua'
for name in ('ReportedRangesTests.lua', 'PointCurveTests.lua'):
    subprocess.run([lua, str(root / 'Tests' / 'Bridge' / name)], cwd=root, check=True)
source = (root / 'Packaging/PanaLux Bridge.lrplugin/ClientUtilities.lua').read_text()
start = source.index('local function PointCurveUpDown(')
end = source.index('\nlocal cg_hsl_parms', start)
context = (root / 'Tests/Bridge/PointCurveContextTests.lua').read_text()
with tempfile.TemporaryDirectory(prefix='panalux-bridge-tests-') as temp:
    test = Path(temp) / 'context.lua'
    test.write_text(source[start:end] + '\n' + context)
    subprocess.run([lua, str(test)], cwd=root, check=True)
