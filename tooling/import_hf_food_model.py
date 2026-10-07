"""Audit, import and benchmark a pinned MIT Food101 classifier (no remote code).

Run with .venv-training-dml310/Scripts/python.exe tooling/import_hf_food_model.py.
Requires TensorFlow 2.10 (legacy Keras), h5py, numpy and Pillow.
Artifacts remain outside app assets; upstream class order is Food101 alphabetical.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import time
import urllib.request

os.environ.setdefault('TF_CPP_MIN_LOG_LEVEL', '2')
REPO = 'ml-debi/EfficientNetB0-Food101'
REVISION = 'e52a2a721d8747db4de993f51325d31f5af375fb'
SHA256 = 'c29128985ad70927d9e3951558e8ddbd255fe701da5e2db105cc6377d8d9cc95'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples-per-class', type=int, default=3)
    parser.add_argument('--output', type=Path, default=Path('training-artifacts/hf-evaluation'))
    parser.add_argument('--reuse-export', action='store_true', help='Benchmark an existing exported TFLite model on CPU')
    parser.add_argument('--audited-samples', type=Path, help='Use selected_samples from evaluate_food_model.py hash-audited report')
    args = parser.parse_args()
    import h5py
    import numpy as np
    import tensorflow as tf
    from PIL import Image
    keras_version = getattr(tf.keras, '__version__', '2')
    if int(keras_version.split('.')[0]) >= 3:
        raise RuntimeError('Use TensorFlow 2.10 environment; legacy nested HDF5 nodes are incompatible with Keras 3.')
    tf.config.set_visible_devices([], 'GPU')
    tf.config.threading.set_intra_op_parallelism_threads(4)
    tf.config.threading.set_inter_op_parallelism_threads(2)
    args.output.mkdir(parents=True, exist_ok=True)
    original = args.output / 'tf_model.h5'
    if not original.exists():
        urllib.request.urlretrieve(f'https://huggingface.co/{REPO}/resolve/{REVISION}/tf_model.h5', original)
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    if digest != SHA256:
        raise ValueError('Upstream artifact SHA256 mismatch')
    adapted = args.output / 'model-float32.h5'
    shutil.copyfile(original, adapted)
    # HDF5 does not enforce Keras safe_mode. Reject executable/custom layers
    # before deserializing and replace legacy mixed precision policies with float32.
    allowed = {'Functional', 'InputLayer', 'Rescaling', 'Normalization', 'ZeroPadding2D',
               'Conv2D', 'BatchNormalization', 'Activation', 'DepthwiseConv2D',
               'GlobalAveragePooling2D', 'Reshape', 'Multiply', 'Dropout', 'Add', 'Dense',
               'VarianceScaling', 'Zeros', 'Ones', 'GlorotUniform'}
    def audit(value):
        if isinstance(value, dict):
            if value.get('class_name') == 'DepthwiseConv2D':
                if value['config'].get('groups', 1) != 1:
                    raise ValueError('Unsupported depthwise convolution groups')
                value['config'].pop('groups', None)
            if 'class_name' in value and 'config' in value:
                if value['class_name'] not in allowed and value['class_name'] != 'Policy':
                    raise ValueError(f"Unapproved serialized object: {value['class_name']}")
            if 'dtype' in value:
                value['dtype'] = 'float32'
            for child in value.values():
                audit(child)
        elif isinstance(value, list):
            for child in value:
                audit(child)
    with h5py.File(adapted, 'r+') as handle:
        config = json.loads(handle.attrs['model_config'])
        audit(config)
        handle.attrs.modify('model_config', json.dumps(config))
    print('Loading audited model', flush=True)
    model = None if args.reuse_export else tf.keras.models.load_model(adapted, compile=False)
    interpreter = None
    if args.reuse_export:
        interpreter = tf.lite.Interpreter(model_path=str(args.output / 'food101-float32.tflite'), num_threads=4)
        interpreter.allocate_tensors()
    print('Selecting held-out sample', flush=True)
    root = Path('entrenarModeloNoAnyadirAGit')
    classes = sorted((root / 'meta/classes.txt').read_text().splitlines())
    remote_config = json.load(urllib.request.urlopen(f'https://huggingface.co/{REPO}/resolve/{REVISION}/config.json'))
    if [remote_config['id2label'][str(i)].replace(' ', '_') for i in range(101)] != classes:
        raise ValueError('Upstream label order does not match local Food101 taxonomy')
    excluded = set()
    for name in ('food-model-v4', 'food-model-v5-es'):
        manifest = Path('training-artifacts', name, 'manifest.jsonl')
        if not manifest.exists():
            continue
        for line in manifest.read_text(encoding='utf-8').splitlines():
            row = json.loads(line)
            if row['split'] in ('train', 'val'):
                excluded.add(os.path.normcase(os.path.abspath(row['image_path'])))
    selected = []
    counts = {}
    if args.audited_samples:
        from train_food_model import _canonicalize_label
        canonical_ids = {_canonicalize_label(label): index for index, label in enumerate(classes)}
        for row in json.loads(args.audited_samples.read_text())['selected_samples']:
            if hashlib.sha256(Path(row['image_path']).read_bytes()).hexdigest() != row.get('sha256'):
                raise ValueError('Audited sample content changed or missing digest')
            if row['label'] in canonical_ids:
                selected.append((Path(row['image_path']), canonical_ids[row['label']]))
    else:
        for item in (root / 'meta/test.txt').read_text().splitlines():
            label = item.split('/')[0]
            path = root / 'images' / f'{item}.jpg'
            if os.path.normcase(os.path.abspath(path)) not in excluded and counts.get(label, 0) < args.samples_per_class:
                selected.append((path, classes.index(label)))
                counts[label] = counts.get(label, 0) + 1
    predictions, timings = [], []
    for index, (path, label) in enumerate(selected):
        with Image.open(path) as picture:
            pixels = np.asarray(picture.convert('RGB').resize((224, 224), Image.Resampling.BILINEAR), dtype=np.float32)[None]
        start = time.perf_counter()
        if interpreter is not None:
            interpreter.set_tensor(interpreter.get_input_details()[0]['index'], pixels / 255.0)
            interpreter.invoke()
            result = interpreter.get_tensor(interpreter.get_output_details()[0]['index'])[0]
        else:
            result = model(pixels, training=False).numpy()[0]
        timings.append((time.perf_counter() - start) * 1000)
        predictions.append({'path': str(path), 'label': classes[label], 'prediction': classes[int(result.argmax())],
                            'top1': bool(result.argmax() == label), 'top5': bool(label in np.argsort(result)[-5:])})
        if index % 50 == 0:
            print(f'Evaluated {index + 1}/{len(selected)}', flush=True)
    # The public app interface consumes [0,1]; upstream embeds /255 scaling.
    if args.reuse_export:
        tflite = (args.output / 'food101-float32.tflite').read_bytes()
    else:
        inputs = tf.keras.Input((224, 224, 3), batch_size=1, dtype='float32')
        wrapped = tf.keras.Model(inputs, model(tf.keras.layers.Rescaling(255.0)(inputs), training=False))
        converter = tf.lite.TFLiteConverter.from_keras_model(wrapped)
        tflite = converter.convert()
        (args.output / 'food101-float32.tflite').write_bytes(tflite)
    report = {'source': f'https://huggingface.co/{REPO}/tree/{REVISION}', 'revision': REVISION,
              'license': 'MIT (repository metadata; no standalone license text provided)', 'sha256': digest,
              'samples': len(selected), 'excluded_training_validation_paths': len(excluded),
              'sample_audit': str(args.audited_samples) if args.audited_samples else 'Combined v4/v5 paths only; image hashes not audited',
              'top1': sum(x['top1'] for x in predictions) / len(predictions),
              'top5': sum(x['top5'] for x in predictions) / len(predictions),
              'median_latency_ms': float(np.median(timings[1:])),
              'backend': 'TFLite CPU 4 threads' if args.reuse_export else 'Keras CPU', 'tflite_bytes': len(tflite),
              'classes': classes, 'predictions': predictions,
              'limitations': ['Upstream training split undocumented: held out only against local training manifest.',
                              '101 classes; excludes extra Spanish dishes supported by current app.',
                              'Latency measured on desktop CPU, not Android device.']}
    (args.output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    from train_food_model import _canonicalize_label
    with (args.output / 'food101_labels.csv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['id', 'name'])
        writer.writerows((index, _canonicalize_label(label)) for index, label in enumerate(classes))
    provenance = {key: report[key] for key in ('source', 'revision', 'license', 'sha256', 'tflite_bytes')}
    provenance.update({'tflite_sha256': hashlib.sha256(tflite).hexdigest(),
                       'input_shape': [1, 224, 224, 3], 'input_range': [0, 1], 'output_classes': 101,
                       'preprocessing': 'RGB stretched to224x224; model embeds255 multiplier then EfficientNet preprocessing',
                       'evaluation_report': 'docs/food_detection_evaluation.md'})
    (args.output / 'food101_model_provenance.json').write_text(json.dumps(provenance, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key not in ('classes', 'predictions')}, indent=2))


if __name__ == '__main__':
    main()
