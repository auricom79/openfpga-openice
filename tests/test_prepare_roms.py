# SPDX-License-Identifier: MIT
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile
import zlib

spec = importlib.util.spec_from_file_location('prepare_roms', Path(__file__).resolve().parents[1] / 'tools/prepare_roms.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PrepareRomsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'roms'
        self.source.mkdir()
        self.output = self.root / 'assets'
        # Synthetic fixtures, not game data.
        self.roms = {'chip-a': b'hello', 'chip-b': b'world!'}
        self.manifest = {'roms': {}, 'streams': []}
        for name, raw in self.roms.items():
            (self.source / name).write_bytes(raw)
            self.manifest['roms'][name] = {'size': len(raw), 'crc32': f'{zlib.crc32(raw):08x}', 'sha1': hashlib.sha1(raw).hexdigest()}
        raw = self.roms['chip-b'] + self.roms['chip-a']
        self.manifest['streams'] = [{'filename': 'output.bin', 'parts': ['chip-b', 'chip-a'], 'size': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}]

    def test_folder_and_idempotent_output(self):
        module.prepare(self.source, self.output, self.manifest)
        self.assertEqual((self.output / 'output.bin').read_bytes(), b'world!hello')
        module.prepare(self.source, self.output, self.manifest)

    def test_zip_does_not_extract_member_paths(self):
        path = self.root / 'input.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            for name, raw in self.roms.items():
                archive.writestr('../' + name, raw)
        module.prepare(path, self.output, self.manifest)
        self.assertFalse((self.root / 'chip-a').exists())
        self.assertEqual((self.output / 'output.bin').read_bytes(), b'world!hello')

    def test_checksum_error_creates_no_output(self):
        (self.source / 'chip-a').write_bytes(b'wrong')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            module.prepare(self.source, self.output, self.manifest)
        self.assertFalse(self.output.exists())

    def test_missing_rom_creates_no_output(self):
        (self.source / 'chip-a').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing ROM'):
            module.prepare(self.source, self.output, self.manifest)
        self.assertFalse(self.output.exists())

    def test_duplicate_zip_member_rejected(self):
        path = self.root / 'input.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('a/chip-a', b'hello')
            archive.writestr('b/chip-a', b'hello')
        with self.assertRaisesRegex(ValueError, 'Duplicate ROM'):
            module.prepare(path, self.output, self.manifest)
        self.assertFalse(self.output.exists())

    def test_existing_different_file_is_preserved(self):
        self.output.mkdir()
        (self.output / 'output.bin').write_bytes(b'keep this')
        with self.assertRaises(FileExistsError):
            module.prepare(self.source, self.output, self.manifest)
        self.assertEqual((self.output / 'output.bin').read_bytes(), b'keep this')


if __name__ == '__main__':
    unittest.main()
