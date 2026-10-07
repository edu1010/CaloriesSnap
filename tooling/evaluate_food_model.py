#!/usr/bin/env python3
"""Compare TFLite exports on a reproducible, leakage-checked test sample.

Example (use the training Python environment):
  python tooling/evaluate_food_model.py --manifest training-artifacts/food-model-v5-es/manifest.jsonl --exclude-manifest training-artifacts/food-model-v4/manifest.jsonl --model assets/models/food_classifier.tflite --model training-artifacts/food-model-v5-es/food_classifier_float32.tflite --model training-artifacts/food-model-v5-es/export/food_classifier_float32.tflite --labels assets/models/food_classifier_labels.csv --output training-artifacts/detection-comparison.json

This measures classification, never calorie or mass accuracy. All supplied
manifests' train/validation paths and SHA256 hashes are excluded before sampling.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def read_manifest(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def select_test(manifest: Path, exclusions: list[Path], per_class: int, seed: int,
                cache_path: Path) -> tuple[list[dict], dict]:
    rows = read_manifest(manifest)
    all_rows = rows + [r for p in exclusions for r in read_manifest(p)]
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    audit = Counter()

    def digest(path: Path) -> str:
        stat = path.stat()
        key = str(path.resolve()).casefold()
        signature = [stat.st_size, stat.st_mtime_ns]
        entry = cache.get(key)
        if entry and entry['signature'] == signature:
            return entry['sha256']
        value = file_hash(path)
        cache[key] = {'signature': signature, 'sha256': value}
        return value

    excluded_paths, excluded_hashes = set(), set()
    for row_index, row in enumerate(all_rows):
        if row['split'] not in ('train', 'val', 'validation'):
            continue
        path = Path(row['image_path']).resolve()
        excluded_paths.add(str(path).casefold())
        if path.is_file():
            excluded_hashes.add(digest(path))
        else:
            audit['missing_training_files'] += 1
        if (row_index + 1) % 5000 == 0:
            print(f'Leakage audit: {row_index + 1}/{len(all_rows)} manifest rows', flush=True)
    # Missing training files make content leakage impossible to verify.
    if audit['missing_training_files']:
        raise ValueError(f"Cannot audit leakage: {audit['missing_training_files']} train/validation files missing")

    grouped = defaultdict(list)
    used_hashes = set()
    for row in sorted(rows, key=lambda r: (r['label'], r['image_path'])):
        if row['split'] != 'test':
            continue
        path = Path(row['image_path']).resolve()
        if not path.is_file():
            audit['missing_test_files'] += 1
            continue
        content_hash = digest(path)
        if str(path).casefold() in excluded_paths or content_hash in excluded_hashes:
            audit['excluded_training_overlap'] += 1
            continue
        if content_hash in used_hashes:
            audit['excluded_test_duplicates'] += 1
            continue
        used_hashes.add(content_hash)
        grouped[row['label']].append({**row, 'image_path': str(path), 'sha256': content_hash})
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache), encoding='utf-8')
    rng = random.Random(seed)
    selected = []
    for label in sorted(grouped):
        candidates = grouped[label]
        rng.shuffle(candidates)
        selected.extend(candidates[:per_class])
    if not selected:
        raise ValueError('No leakage-free test samples available')
    return selected, {**audit, 'eligible_per_class': {k: len(v) for k, v in grouped.items()},
                      'excluded_training_paths': len(excluded_paths),
                      'excluded_training_hashes': len(excluded_hashes)}


def image_tensor(tf, path: str, height: int, width: int, mode: str) -> np.ndarray:
    image = tf.image.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
    image = tf.image.convert_image_dtype(image, tf.float32)
    if mode == 'crop':
        shape = tf.shape(image)
        side = tf.minimum(shape[0], shape[1])
        image = tf.image.crop_to_bounding_box(image, (shape[0] - side) // 2,
                                             (shape[1] - side) // 2, side, side)
    return tf.image.resize(image, [height, width], antialias=True).numpy()[None, ...]


def evaluate(tf, model: Path, samples: list[dict], labels: list[str], mode: str, threads: int) -> dict:
    runner = tf.lite.Interpreter(model_path=str(model), num_threads=threads)
    runner.allocate_tensors()
    inp, out = runner.get_input_details()[0], runner.get_output_details()[0]
    if int(out['shape'][-1]) != len(labels):
        raise ValueError(f'{model}: output/label count mismatch')
    height, width = map(int, inp['shape'][1:3])
    class_counts, class_correct = Counter(), Counter()
    confusion, predictions = Counter(), []
    top5_hits = 0
    for index, sample in enumerate(samples):
        value = image_tensor(tf, sample['image_path'], height, width, mode)
        if np.issubdtype(inp['dtype'], np.integer):
            scale, zero = inp['quantization']
            if scale <= 0:
                raise ValueError('Invalid input quantization')
            bounds = np.iinfo(inp['dtype'])
            value = np.clip(np.rint(value / scale + zero), bounds.min, bounds.max)
        runner.set_tensor(inp['index'], value.astype(inp['dtype']))
        runner.invoke()
        scores = runner.get_tensor(out['index'])[0].astype(np.float64)
        if np.issubdtype(out['dtype'], np.integer):
            scale, zero = out['quantization']
            scores = (scores - zero) * scale
        ranking = np.argsort(-scores, kind='stable')[:5]
        truth, predicted = sample['label'], labels[ranking[0]]
        class_counts[truth] += 1
        class_correct[truth] += int(truth == predicted)
        top5_hits += int(truth in [labels[i] for i in ranking])
        confusion[(truth, predicted)] += int(truth != predicted)
        predictions.append({'path': sample['image_path'], 'truth': truth, 'predicted': predicted,
                            'confidence': float(scores[ranking[0]]),
                            'margin': float(scores[ranking[0]] - scores[ranking[1]]),
                            'top5': [labels[i] for i in ranking]})
        if (index + 1) % 100 == 0:
            print(f'{model.name}/{mode}: {index + 1}/{len(samples)}', flush=True)
    recalls = {k: class_correct[k] / n for k, n in class_counts.items()}
    return {'model': str(model.resolve()), 'sha256': file_hash(model), 'mode': mode,
            'input_shape': inp['shape'].tolist(), 'input_dtype': str(inp['dtype']),
            'samples': len(samples), 'top1': sum(class_correct.values()) / len(samples),
            'top5': top5_hits / len(samples), 'macro_recall': sum(recalls.values()) / len(recalls),
            'per_class_recall': recalls, 'per_class_count': dict(class_counts),
            'largest_confusions': [{'truth': a, 'predicted': b, 'count': n}
                                   for (a, b), n in confusion.most_common(25) if n],
            'predictions': predictions}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--exclude-manifest', type=Path, action='append', default=[])
    parser.add_argument('--model', type=Path, action='append', required=True)
    parser.add_argument('--labels', type=Path, required=True)
    parser.add_argument('--per-class', type=int, default=10)
    parser.add_argument('--seed', type=int, default=20261007)
    parser.add_argument('--threads', type=int, default=4)
    parser.add_argument('--mode', action='append', choices=['crop', 'stretch'])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.per_class < 1:
        parser.error('--per-class must be positive')
    os.environ.setdefault('WRAPT_DISABLE_EXTENSIONS', '1')
    import tensorflow as tf
    with args.labels.open(encoding='utf-8-sig', newline='') as stream:
        label_rows = sorted(csv.DictReader(stream), key=lambda r: int(r['id']))
        labels = [r['name'] for r in label_rows]
    if [int(r['id']) for r in label_rows] != list(range(len(labels))):
        raise ValueError('Classifier label IDs must be contiguous from zero')
    samples, audit = select_test(args.manifest, args.exclude_manifest, args.per_class,
                                 args.seed, args.output.with_suffix('.hash-cache.json'))
    unknown = set(s['label'] for s in samples) - set(labels)
    if unknown:
        raise ValueError(f'Test labels absent from classifier: {sorted(unknown)}')
    report = {'seed': args.seed, 'per_class': args.per_class, 'manifest': str(args.manifest.resolve()),
              'manifest_sha256': file_hash(args.manifest), 'labels_sha256': file_hash(args.labels),
              'exclusion_manifests': [str(p.resolve()) for p in args.exclude_manifest],
              'audit': audit, 'selected_samples': samples,
              'tested_class_count': len(set(s['label'] for s in samples)),
              'missing_test_classes': sorted(set(labels) - set(s['label'] for s in samples)),
              'scope': 'Image classification only; no measurement of portion or calorie accuracy',
              'results': []}
    for model in args.model:
        for mode in args.mode or ['crop', 'stretch']:
            report['results'].append(evaluate(tf, model, samples, labels, mode, args.threads))
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
            result = report['results'][-1]
            print(f"{model}/{mode}: top1={result['top1']:.4f} top5={result['top5']:.4f}", flush=True)


if __name__ == '__main__':
    main()
