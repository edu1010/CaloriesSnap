"""Split/leakage regressions for train_food_model on tiny fake datasets (no TensorFlow)."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import train_food_model as tm

CLASSES = ('apple_pie', 'fried_rice')
TRAIN_IDS = [f't{i}' for i in range(10)]
TEST_IDS = [f'e{i}' for i in range(4)]


def image_bytes(tag: str) -> bytes:
    # Unique per tag and above the 1024 byte minimum file size.
    return (tag.encode() + b'|') * 300


def write_image(path: Path, tag: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(image_bytes(tag))
    return path


def make_food101(root: Path) -> None:
    train_lines, test_lines = [], []
    for cls in CLASSES:
        for image_id in TRAIN_IDS:
            write_image(root / 'images' / cls / f'{image_id}.jpg', f'{cls}/{image_id}')
            train_lines.append(f'{cls}/{image_id}')
        for image_id in TEST_IDS:
            write_image(root / 'images' / cls / f'{image_id}.jpg', f'{cls}/{image_id}')
            test_lines.append(f'{cls}/{image_id}')
    # A train-listed file with the exact bytes of an official test image.
    write_image(root / 'images' / 'apple_pie' / 'leak.jpg', 'apple_pie/e0')
    train_lines.append('apple_pie/leak')
    (root / 'meta').mkdir(parents=True)
    (root / 'meta' / 'train.txt').write_text('\n'.join(train_lines) + '\n', encoding='utf-8')
    (root / 'meta' / 'test.txt').write_text('\n'.join(test_lines) + '\n', encoding='utf-8')


def make_nutrition5k(root: Path) -> None:
    rows = []
    for index in range(3):
        dish_id = f'dish_{index}'
        write_image(root / 'imagery' / 'realsense_overhead' / dish_id / 'rgb.png', dish_id)
        rows.append(f'{dish_id},100,200,1,1,1,ingr_1,white rice,150,1,1,1,1')
    (root / 'metadata').mkdir(parents=True)
    (root / 'metadata' / 'dish_metadata_cafe1.csv').write_text('\n'.join(rows) + '\n',
                                                               encoding='utf-8')


def official_paths(root: Path, ids: list[str]) -> set[str]:
    return {str((root / 'images' / cls / f'{image_id}.jpg').resolve())
            for cls in CLASSES for image_id in ids}


def run_main(root: Path, out_name: str, *extra: str) -> list[dict]:
    out_dir = root / out_name
    argv = ['train_food_model.py',
            '--food101-root', str(root / 'food101'),
            '--spanish-root', str(root / 'missing-spanish'),
            '--ai4food-root', str(root / 'missing-ai4food'),
            '--nutrition5k-root', str(root / 'nutrition5k'),
            '--output-dir', str(out_dir),
            '--min-class-samples', '1',
            '--min-file-size-bytes', '1024',
            '--baseline-report-path', str(root / 'missing-report.json'),
            '--baseline-manifest-path', str(root / 'missing-manifest.jsonl'),
            *extra]
    with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
        exit_code = tm.main()
    if exit_code != 0:
        raise AssertionError(f'main() returned {exit_code}')
    lines = (out_dir / 'manifest.jsonl').read_text(encoding='utf-8').splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def fake_sample(name: str, split: str, source: str = 'food101_local', locked: bool = False):
    return tm.Sample(image_path=f'/fake/{source}/A/{name}.jpg', label='A', split=split,
                     source=source, raw_label='a', split_locked=locked)


class OfficialTestSplitTest(unittest.TestCase):
    def test_scan_locks_official_test_and_leaves_validation_to_balancing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'food101'
            make_food101(root)
            samples = tm._scan_food101(root)
            locked = {s.image_path for s in samples if s.split_locked}
            self.assertEqual(locked, official_paths(root, TEST_IDS))
            self.assertTrue(all(s.split == 'test' for s in samples if s.split_locked))
            self.assertEqual({s.split for s in samples if not s.split_locked}, {'train'})

    def test_rebalance_never_moves_locked_test_and_takes_val_from_train_pool(self):
        locked = [fake_sample(f'e{i}', 'test', locked=True) for i in range(20)]
        pool = [fake_sample(f't{i}', 'train') for i in range(80)]
        other = [fake_sample(f's{i}', 'train', source='spanish_scraped') for i in range(30)]
        samples = locked + pool + other

        once = tm._rebalance_splits(samples, random_seed=42, train_ratio=0.7, val_ratio=0.15)
        # Different ratios on the second pass must still not touch the test set.
        twice = tm._rebalance_splits(once, random_seed=42, train_ratio=0.5, val_ratio=0.25)
        for result in (once, twice):
            food101 = [s for s in result if s.source == 'food101_local']
            self.assertEqual({s.image_path for s in food101 if s.split == 'test'},
                             {s.image_path for s in locked})
            pool_splits = {s.split for s in food101 if not s.split_locked}
            self.assertEqual(pool_splits, {'train', 'val'})
            self.assertEqual(len(result), len(samples))
            tm._verify_split_integrity(result)

        val = [s for s in once if s.source == 'food101_local' and s.split == 'val']
        self.assertEqual(len(val), round(80 * 0.15 / 0.85))
        # A source without an official test split still gets its own holdout.
        self.assertEqual({s.split for s in once if s.source == 'spanish_scraped'},
                         {'train', 'val', 'test'})

    def test_rebalance_is_stable_across_passes_and_input_order(self):
        samples = ([fake_sample(f'e{i}', 'test', locked=True) for i in range(5)]
                   + [fake_sample(f't{i}', 'train') for i in range(40)])
        kwargs = {'random_seed': 7, 'train_ratio': 0.7, 'val_ratio': 0.15}
        first = tm._rebalance_splits(samples, **kwargs)
        second = tm._rebalance_splits(list(reversed(first)), **kwargs)
        self.assertEqual({(s.image_path, s.split) for s in first},
                         {(s.image_path, s.split) for s in second})

    def test_cap_keeps_every_locked_test_sample(self):
        locked = [fake_sample(f'e{i}', 'test', locked=True) for i in range(6)]
        pool = [fake_sample(f't{i}', 'train') for i in range(30)]
        capped = tm._cap_samples_per_class(pool + locked, max_per_class=10, random_seed=1)
        self.assertEqual(len(capped), 10)
        self.assertEqual(sum(s.split_locked for s in capped), 6)

    def test_verify_rejects_moved_test_sample_and_cross_split_path(self):
        with self.assertRaisesRegex(RuntimeError, 'Locked test sample'):
            tm._verify_split_integrity([fake_sample('e0', 'val', locked=True)])
        with self.assertRaisesRegex(RuntimeError, 'both'):
            tm._verify_split_integrity([fake_sample('x', 'train'), fake_sample('x', 'test')])


class DedupeLeakageTest(unittest.TestCase):
    def test_identical_bytes_keep_the_official_test_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            test_path = write_image(root / 'test.jpg', 'same')
            train_path = write_image(root / 'train-copy.jpg', 'same')
            scraped_path = write_image(root / 'scraped-copy.jpg', 'same')
            unique_path = write_image(root / 'unique.jpg', 'other')
            samples = [
                tm.Sample(str(train_path), 'A', 'train', 'food101_local', 'a'),
                tm.Sample(str(scraped_path), 'B', 'train', 'spanish_scraped', 'b'),
                tm.Sample(str(test_path), 'A', 'test', 'food101_local', 'a', split_locked=True),
                tm.Sample(str(unique_path), 'A', 'train', 'food101_local', 'a'),
            ]
            kept, stats, dropped = tm._deduplicate_samples(samples, hash_bytes=65536)
            self.assertEqual({s.image_path for s in kept}, {str(test_path), str(unique_path)})
            self.assertEqual(stats['dedupe_removed'], 2)
            self.assertEqual({row.image_path for row in dropped},
                             {str(train_path), str(scraped_path)})

    def test_repeated_path_is_collapsed_even_without_content_hashing(self):
        # No file needed: with content hashing off, identity is the path alone.
        samples = [fake_sample('x', 'train'), fake_sample('x', 'test', locked=True),
                   fake_sample('y', 'train')]
        kept, _, _ = tm._deduplicate_samples(samples, hash_bytes=65536, content_hash=False)
        self.assertEqual(len(kept), 2)
        self.assertEqual([s.split for s in kept if s.image_path.endswith('x.jpg')], ['test'])

    def test_ai4food_copies_of_food101_are_dropped(self):
        samples = [
            tm.Sample('/d/fried_rice_Food101_0010.jpg', 'Fried Rice', 'train', 'ai4food_product',
                      'fried rice'),
            tm.Sample('/d/fried_rice_UECFood_0010.jpg', 'Fried Rice', 'train', 'ai4food_product',
                      'fried rice'),
            tm.Sample('/d/x_Food101_1.jpg', 'Fried Rice', 'train', 'food101_local', 'fried_rice'),
        ]
        kept, dropped = tm._drop_ai4food_food101_copies(samples)
        self.assertEqual(kept, samples[1:])
        self.assertEqual([row.reason for row in dropped], ['ai4food_food101_copy_unknown_split'])


class ManifestBuildTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        make_food101(self.root / 'food101')
        make_nutrition5k(self.root / 'nutrition5k')
        self.test_paths = official_paths(self.root / 'food101', TEST_IDS)
        self.train_paths = official_paths(self.root / 'food101', TRAIN_IDS)

    def test_manifest_test_split_is_exactly_the_official_one(self):
        rows = run_main(self.root, 'out')
        by_split = {split: {r['image_path'] for r in rows if r['split'] == split}
                    for split in tm.SPLITS}
        self.assertEqual(by_split['test'], self.test_paths)
        self.assertTrue(all(r['split_locked'] for r in rows if r['split'] == 'test'))
        self.assertTrue(by_split['val'])
        self.assertEqual(by_split['train'] | by_split['val'], self.train_paths)
        self.assertFalse(by_split['train'] & by_split['val'])
        # The train-listed byte copy of an official test image is gone.
        leak = str((self.root / 'food101' / 'images' / 'apple_pie' / 'leak.jpg').resolve())
        self.assertNotIn(leak, {r['image_path'] for r in rows})

        reread = tm._read_manifest(self.root / 'out' / 'manifest.jsonl')
        self.assertEqual({s.image_path for s in reread if s.split_locked}, self.test_paths)

    def test_nutrition5k_is_excluded_unless_opted_in_and_then_train_only(self):
        default_rows = run_main(self.root, 'out-default')
        self.assertNotIn('nutrition5k_overhead', {r['source'] for r in default_rows})

        opted_rows = run_main(self.root, 'out-opt-in', '--include-nutrition5k-keyword-labels')
        nutrition = [r for r in opted_rows if r['source'] == 'nutrition5k_overhead']
        self.assertEqual(len(nutrition), 3)
        self.assertEqual({r['split'] for r in nutrition}, {'train'})
        self.assertEqual({r['label'] for r in nutrition}, {'Fried Rice'})
        # Opting in must not change the official test set.
        self.assertEqual({r['image_path'] for r in opted_rows if r['split'] == 'test'},
                         self.test_paths)

    def test_legacy_manifest_without_lock_field_still_loads(self):
        manifest = self.root / 'legacy.jsonl'
        manifest.write_text(json.dumps({'image_path': 'a.jpg', 'label': 'A', 'split': 'test'}),
                            encoding='utf-8')
        self.assertEqual(tm._read_manifest(manifest)[0].split_locked, False)


if __name__ == '__main__':
    unittest.main()
