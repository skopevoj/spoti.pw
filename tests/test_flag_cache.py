"""Run the pipeline's real cache block against a harmless mock extractor."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PIPELINE = (ROOT / 'scripts/pipeline.sh').read_text()
BLOCK = PIPELINE[PIPELINE.index('# Cache both the source'):PIPELINE.index('echo "==> building tweak"')]


class FlagCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for path in ('out', 'scripts', 'tweak/Sources/Shared/Flags'):
            (self.root / path).mkdir(parents=True)
        self.table = self.root / 'tweak/Sources/Shared/Flags/SGFlagList.m'
        self.input = self.root / 'input.ipa'
        self.input.write_text('source A')
        self.extractor = self.root / 'scripts/extract-flags.py'
        self.extractor.write_text('#!/bin/bash\nset -e\necho run >> "$ROOT/out/runs"\ncat "$1" > "$ROOT/tweak/Sources/Shared/Flags/SGFlagList.m"\n')
        self.extractor.chmod(0o755)
        self.env = dict(os.environ, ROOT=str(self.root), IN=str(self.input))

    def run_cache(self):
        result = subprocess.run(['/bin/bash', '-c', 'set -euo pipefail\n' + BLOCK],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return (self.root / 'out/runs').read_text().count('run')

    def test_unchanged_source_reuses_table(self):
        self.assertEqual(self.run_cache(), 1)
        self.assertEqual(self.run_cache(), 1)

    def test_new_ipa_regenerates(self):
        self.run_cache()
        self.input.write_text('source B')
        self.assertEqual(self.run_cache(), 2)
        self.assertEqual(self.table.read_text(), 'source B')

    def test_manual_flags_from_other_ipa_regenerates(self):
        self.run_cache()
        self.table.write_text('manually generated source B')
        self.assertEqual(self.run_cache(), 2)
        self.assertEqual(self.table.read_text(), 'source A')

    def test_updated_extractor_regenerates(self):
        self.run_cache()
        self.extractor.write_text(self.extractor.read_text() + '# changed extractor\n')
        self.assertEqual(self.run_cache(), 2)

    def test_missing_table_regenerates(self):
        self.run_cache()
        self.table.unlink()
        self.assertEqual(self.run_cache(), 2)


if __name__ == '__main__':
    unittest.main()
