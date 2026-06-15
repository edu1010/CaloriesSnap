#!/usr/bin/env python3
"""Export TFLite models from trained weights and optionally deploy to app assets."""

from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path

import tensorflow as tf

import train_food_model as tm


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export TFLite from trained weights.")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--classes", type=Path, required=True)
    parser.add_argument("--weights", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--backbone", type=str, default="efficientnetv2b0", choices=sorted(tm.BACKBONES))
    parser.add_argument("--image-size", type=int, default=160)
    parser.add_argument("--dropout", type=float, default=0.3)
    parser.add_argument("--representative-size", type=int, default=400)
    parser.add_argument(
        "--deploy-model-type",
        type=str,
        choices=["none", "float32", "int8"],
        default="none",
        help="Which exported model to copy into assets/models.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    manifest = tm._read_manifest(args.manifest)
    classes = [line.strip() for line in args.classes.read_text(encoding="utf-8").splitlines() if line.strip()]

    tf.keras.mixed_precision.set_global_policy("float32")
    model, _ = tm._build_model(
        num_classes=len(classes),
        image_size=args.image_size,
        backbone=args.backbone,
        dropout=args.dropout,
    )
    model.load_weights(str(args.weights))

    @tf.function(
        input_signature=[
            tf.TensorSpec(
                shape=[1, args.image_size, args.image_size, 3],
                dtype=tf.float32,
                name="image",
            ),
        ],
    )
    def serving(image):
        return {"probabilities": model(image, training=False)}

    concrete = serving.get_concrete_function()

    float_converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    float_converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    float_model = float_converter.convert()
    float_path = args.output_dir / "food_classifier_float32.tflite"
    float_path.write_bytes(float_model)

    rep_candidates = [s for s in manifest if s.split == "train"]
    random.Random(42).shuffle(rep_candidates)
    rep_subset = rep_candidates[: max(80, args.representative_size)]

    def representative_dataset():
        for sample in rep_subset:
            img = tf.io.read_file(sample.image_path)
            img = tf.image.decode_image(img, channels=3, expand_animations=False)
            img = tf.image.convert_image_dtype(img, tf.float32)
            img = tf.image.resize(img, [args.image_size, args.image_size], antialias=True)
            yield [tf.expand_dims(img, axis=0)]

    int8_converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    int8_converter.optimizations = [tf.lite.Optimize.DEFAULT]
    int8_converter.representative_dataset = representative_dataset
    int8_converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    int8_converter.inference_input_type = tf.int8
    int8_converter.inference_output_type = tf.int8
    int8_model = int8_converter.convert()
    int8_path = args.output_dir / "food_classifier_int8.tflite"
    int8_path.write_bytes(int8_model)

    labels_path = args.output_dir / "food_classifier_labels.csv"
    with labels_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name"])
        for idx, class_name in enumerate(classes):
            writer.writerow([idx, class_name])

    if args.deploy_model_type != "none":
        asset_model_path = Path("assets/models/food_classifier.tflite")
        asset_labels_path = Path("assets/models/food_classifier_labels.csv")
        if args.deploy_model_type == "int8":
            asset_model_path.write_bytes(int8_model)
        else:
            asset_model_path.write_bytes(float_model)
        asset_labels_path.write_text(labels_path.read_text(encoding="utf-8"), encoding="utf-8")

    print(f"[ok] float32: {float_path} ({float_path.stat().st_size} bytes)")
    print(f"[ok] int8: {int8_path} ({int8_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
