"""Evaluate fixed Spanish-specialist routing on an existing hash-audited sample.

Run evaluate_food_model.py first, then pass its report here. This does not tune
thresholds or weights and never installs/replaces application model assets.
"""
import argparse
import csv
import json
import os
from pathlib import Path

import evaluate_food_model as evaluation
from train_food_model import _canonicalize_label


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--food101-model', type=Path, required=True)
    parser.add_argument('--food101-labels', type=Path, required=True)
    parser.add_argument('--specialist-model', type=Path, default=Path('assets/models/food_classifier.tflite'))
    parser.add_argument('--specialist-labels', type=Path, default=Path('assets/models/food_classifier_labels.csv'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
    import tensorflow as tf
    baseline = json.loads(args.baseline.read_text(encoding='utf-8'))
    if evaluation.file_hash(args.specialist_labels) != baseline['labels_sha256']:
        raise ValueError('Specialist label map has changed since the baseline benchmark')
    for sample in baseline['selected_samples']:
        if evaluation.file_hash(Path(sample['image_path'])) != sample.get('sha256'):
            raise ValueError(f"Audited sample content changed or missing digest: {sample['image_path']}")
    def read_labels(path):
        with path.open(encoding='utf-8-sig', newline='') as stream:
            return [_canonicalize_label(row['name']) for row in sorted(csv.DictReader(stream), key=lambda r: int(r['id']))]
    labels = read_labels(args.food101_labels)
    spanish = sorted(set(read_labels(args.specialist_labels)) - set(labels))
    matches = [row for row in baseline['results'] if Path(row['model']).resolve() == args.specialist_model.resolve() and row['mode'] == 'stretch']
    if len(matches) != 1:
        raise ValueError('Need exactly one baseline specialist result with stretch preprocessing')
    specialist = matches[0]
    if specialist['sha256'] != evaluation.file_hash(args.specialist_model):
        raise ValueError('Specialist model has changed since the baseline benchmark')
    food101 = evaluation.evaluate(tf, args.food101_model, baseline['selected_samples'], labels, 'stretch', 4)
    predictions = []
    for local, generic in zip(specialist['predictions'], food101['predictions']):
        if local['path'] != generic['path'] or local['truth'] != generic['truth']:
            raise ValueError('Prediction sample order mismatch')
        chosen = local if local['predicted'] in spanish and local['confidence'] >= .03 else generic
        predictions.append({**chosen, 'route': 'spanish' if chosen is local else 'food101'})
    def metrics(rows):
        return {'samples': len(rows), 'top1': sum(row['truth'] == row['predicted'] for row in rows) / len(rows),
                'top5': sum(row['truth'] in row['top5'] for row in rows) / len(rows)}
    report = {'scope': 'Image classification only; no portion, nutrition or calorie accuracy measured',
              'policy': 'Specialist top1 is Spanish extra class and confidence >=0.03 -> specialist, otherwise Food101',
              'baseline_sha256': evaluation.file_hash(args.baseline),
              'food101_labels_sha256': evaluation.file_hash(args.food101_labels),
              'audit': baseline['audit'], 'spanish_classes': spanish,
              'specialist': specialist, 'food101': food101,
              'overall': metrics(predictions),
              'spanish': metrics([row for row in predictions if row['truth'] in spanish]),
              'supported101': metrics([row for row in predictions if row['truth'] in labels]),
              'food101_supported101': metrics([row for row in food101['predictions'] if row['truth'] in labels]),
              'predictions': predictions}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({key: report[key] for key in ('overall', 'spanish', 'supported101', 'food101_supported101')}, indent=2))


if __name__ == '__main__':
    main()
