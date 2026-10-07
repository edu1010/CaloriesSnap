"""Exercise test selection without loading TensorFlow or the large dataset."""
import json
import tempfile
import unittest
from pathlib import Path

from evaluate_food_model import select_test


class TestSelection(unittest.TestCase):
    def test_excludes_content_and_path_leakage_and_is_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = []
            for name, contents, split, label in [
                ('train.jpg', b'same image', 'train', 'A'),
                ('copied-test.jpg', b'same image', 'test', 'A'),
                ('good-a.jpg', b'unique a', 'test', 'A'),
                ('good-a-copy.jpg', b'unique a', 'test', 'A'),
                ('good-b.jpg', b'unique b', 'test', 'B'),
            ]:
                path = root / name
                path.write_bytes(contents)
                rows.append({'image_path': str(path), 'split': split, 'label': label})
            # Same path is excluded even when a manifest mistakenly repeats it.
            rows.append({**rows[0], 'split': 'test'})
            manifest = root / 'manifest.jsonl'
            manifest.write_text('\n'.join(json.dumps(r) for r in rows))
            args = (manifest, [], 10, 42, root / 'cache.json')
            selected, audit = select_test(*args)
            self.assertEqual(len(selected), 2)
            self.assertEqual(audit['excluded_training_overlap'], 2)
            self.assertEqual(audit['excluded_test_duplicates'], 1)
            self.assertEqual(selected, select_test(*args)[0])

    def test_missing_training_file_fails_instead_of_claiming_audited_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / 'manifest.jsonl'
            manifest.write_text(json.dumps({'image_path': str(root / 'missing.jpg'),
                                             'split': 'train', 'label': 'A'}))
            with self.assertRaisesRegex(ValueError, 'Cannot audit leakage'):
                select_test(manifest, [], 10, 42, root / 'cache.json')


if __name__ == '__main__':
    unittest.main()
