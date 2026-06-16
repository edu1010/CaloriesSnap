#!/usr/bin/env python3
"""Recover a trained checkpoint whose nested-submodel weights fail Keras'
topological load_weights ("axes don't match array"), by assigning weights
directly from the HDF5 file via set_weights, then export float32 + int8 TFLite.

Bypasses tf.keras load_weights' preprocess_weights_for_loading entirely.
"""
from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path

import h5py
import numpy as np
import tensorflow as tf

import train_food_model as tm


def _read_group_arrays(group: h5py.Group) -> list[np.ndarray]:
    """Return weight arrays of an HDF5 layer group in saved order."""
    names = group.attrs.get("weight_names")
    if names is None:
        return []
    ordered = []
    for n in names:
        key = n.decode("utf-8") if isinstance(n, (bytes, bytearray)) else n
        ordered.append(np.asarray(group[key]))
    return ordered


def assign_weights_from_h5(model: tf.keras.Model, h5_path: str) -> None:
    """Match weights by variable NAME (not save order), since the nested
    submodel's HDF5 weight_names are ordered differently from model.weights."""
    with h5py.File(h5_path, "r") as f:
        name_to_arr: dict[str, np.ndarray] = {}
        for layer in model.layers:
            if layer.name not in f:
                continue
            group = f[layer.name]
            names = group.attrs.get("weight_names")
            if names is None:
                continue
            for n in names:
                key = n.decode("utf-8") if isinstance(n, (bytes, bytearray)) else n
                name_to_arr[key] = np.asarray(group[key])

        ordered: list[np.ndarray] = []
        for var in model.weights:
            vname = var.name
            arr = name_to_arr.get(vname)
            if arr is None:
                cand = [k for k in name_to_arr if k.endswith(vname) or vname.endswith(k)]
                if len(cand) != 1:
                    raise RuntimeError(
                        f"No unique h5 match for variable {vname} (candidates={cand[:5]})"
                    )
                arr = name_to_arr[cand[0]]
            if tuple(var.shape) != tuple(arr.shape):
                raise RuntimeError(
                    f"Shape mismatch for {vname}: model {tuple(var.shape)} vs h5 {tuple(arr.shape)}"
                )
            ordered.append(arr)
        model.set_weights(ordered)


def evaluate(model, samples, image_size, classes, limit=400) -> tuple[float, float, int]:
    idx = {c: i for i, c in enumerate(classes)}
    val = [s for s in samples if s.split == "val"]
    random.Random(0).shuffle(val)
    val = val[:limit]

    def load_img(p):
        x = tf.io.read_file(p)
        x = tf.image.decode_image(x, channels=3, expand_animations=False)
        x = tf.image.convert_image_dtype(x, tf.float32)
        return tf.image.resize(x, [image_size, image_size], antialias=True)

    correct = top5 = n = 0
    B = 50
    for i in range(0, len(val), B):
        batch = val[i : i + B]
        xs = tf.stack([load_img(s.image_path) for s in batch])
        pr = model(xs, training=False).numpy()
        for s, p in zip(batch, pr):
            gt = idx.get(s.label, -1)
            top = p.argsort()[-5:][::-1]
            correct += int(gt == top[0])
            top5 += int(gt in top)
            n += 1
    return (correct / max(n, 1), top5 / max(n, 1), n)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--classes", type=Path, required=True)
    ap.add_argument("--weights", type=Path, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--backbone", default="efficientnetv2b0")
    ap.add_argument("--image-size", type=int, default=224)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--representative-size", type=int, default=400)
    ap.add_argument("--min-top1", type=float, default=0.40)
    args = ap.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    tf.keras.mixed_precision.set_global_policy("float32")
    classes = [l.strip() for l in args.classes.read_text(encoding="utf-8").splitlines() if l.strip()]
    manifest = tm._read_manifest(args.manifest)

    model, _ = tm._build_model(
        num_classes=len(classes),
        image_size=args.image_size,
        backbone=args.backbone,
        dropout=args.dropout,
    )
    assign_weights_from_h5(model, str(args.weights))
    print(f"[ok] assigned {len(model.weights)} weight tensors from h5")

    top1, top5, n = evaluate(model, manifest, args.image_size, classes)
    print(f"[verify] val n={n} top1={top1:.4f} top5={top5:.4f}")
    if top1 < args.min_top1:
        print(f"[error] top1 {top1:.4f} below threshold {args.min_top1}; aborting export.")
        return 2

    @tf.function(input_signature=[tf.TensorSpec([1, args.image_size, args.image_size, 3], tf.float32, name="image")])
    def serving(image):
        return {"probabilities": model(image, training=False)}

    concrete = serving.get_concrete_function()

    float_conv = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    float_conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    float_model = float_conv.convert()
    float_path = args.output_dir / "food_classifier_float32.tflite"
    float_path.write_bytes(float_model)
    print(f"[ok] float32: {float_path} ({float_path.stat().st_size} bytes)")

    rep = [s for s in manifest if s.split == "train"]
    random.Random(42).shuffle(rep)
    rep = rep[: max(80, args.representative_size)]

    def representative_dataset():
        for s in rep:
            x = tf.io.read_file(s.image_path)
            x = tf.image.decode_image(x, channels=3, expand_animations=False)
            x = tf.image.convert_image_dtype(x, tf.float32)
            x = tf.image.resize(x, [args.image_size, args.image_size], antialias=True)
            yield [tf.expand_dims(x, 0)]

    int8_conv = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    int8_conv.optimizations = [tf.lite.Optimize.DEFAULT]
    int8_conv.representative_dataset = representative_dataset
    int8_conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    int8_conv.inference_input_type = tf.int8
    int8_conv.inference_output_type = tf.int8
    int8_model = int8_conv.convert()
    int8_path = args.output_dir / "food_classifier_int8.tflite"
    int8_path.write_bytes(int8_model)
    print(f"[ok] int8: {int8_path} ({int8_path.stat().st_size} bytes)")

    labels_path = args.output_dir / "food_classifier_labels.csv"
    with labels_path.open("w", encoding="utf-8", newline="") as fh:
        wtr = csv.writer(fh)
        wtr.writerow(["id", "name"])
        for i, c in enumerate(classes):
            wtr.writerow([i, c])
    print(f"[ok] labels: {labels_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
