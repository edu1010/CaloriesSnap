#!/usr/bin/env python3
"""Resume fine-tuning from a saved checkpoint (best.weights.h5) WITHOUT redoing
the head phase, then export float32 + int8 TFLite.

Loads the checkpoint with a name-based assignment that bypasses the broken
tf.keras topological load_weights for nested submodels (see recover_export.py).

Example (close GPU-heavy apps first — Unity, games, browsers):
  PYTHONPATH=tooling .venv-training-dml310/Scripts/python.exe tooling/resume_train.py \
    --output-dir training-artifacts/food-model-v4 \
    --weights training-artifacts/food-model-v4/best.weights.h5 \
    --manifest training-artifacts/food-model-v4/manifest.jsonl \
    --classes training-artifacts/food-model-v4/classes.txt \
    --image-size 224 --batch-size 48 --epochs-finetune 20 --unfreeze-layers 120 \
    --representative-size 300 --deploy
"""
from __future__ import annotations

import argparse
import csv
import random
from pathlib import Path

import tensorflow as tf

import train_food_model as tm
from recover_export import assign_weights_from_h5, evaluate


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--weights", type=Path, required=True)
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--classes", type=Path, required=True)
    ap.add_argument("--backbone", default="efficientnetv2b0")
    ap.add_argument("--image-size", type=int, default=224)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--batch-size", type=int, default=48)
    ap.add_argument("--epochs-finetune", type=int, default=20)
    ap.add_argument("--learning-rate-finetune", type=float, default=1e-4)
    ap.add_argument("--unfreeze-layers", type=int, default=120)
    ap.add_argument("--focal-gamma", type=float, default=1.0)
    ap.add_argument("--focal-label-smoothing", type=float, default=0.02)
    ap.add_argument("--balance-classes", action="store_true", default=True)
    ap.add_argument("--class-weight-max", type=float, default=5.0)
    ap.add_argument("--mixup-alpha", type=float, default=0.2)
    ap.add_argument("--cutmix-alpha", type=float, default=0.8)
    ap.add_argument("--cutmix-prob", type=float, default=0.35)
    ap.add_argument("--representative-size", type=int, default=300)
    ap.add_argument("--patience", type=int, default=5)
    ap.add_argument("--deploy", action="store_true")
    args = ap.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    tm._configure_tensorflow_runtime()
    mp = tm._set_mixed_precision_if_supported(True)
    print(f"[info] mixed precision policy: {mp}")

    classes = [l.strip() for l in args.classes.read_text(encoding="utf-8").splitlines() if l.strip()]
    samples = tm._read_manifest(args.manifest)

    train_ds, val_ds, _test_ds, eval_val_ds, eval_test_ds = tm._build_tf_datasets(
        samples,
        classes,
        args.image_size,
        args.batch_size,
        balance_classes=args.balance_classes,
        class_weight_max=args.class_weight_max,
        mixup_alpha=args.mixup_alpha,
        cutmix_alpha=args.cutmix_alpha,
        cutmix_prob=args.cutmix_prob,
        cache_train=False,
        cache_dir=args.output_dir / "tf_cache",
    )

    # Build at float32 to assign weights cleanly, then continue under mixed policy.
    model, base = tm._build_model(
        num_classes=len(classes),
        image_size=args.image_size,
        backbone=args.backbone,
        dropout=args.dropout,
    )
    assign_weights_from_h5(model, str(args.weights))
    print("[ok] checkpoint weights assigned (name-based)")

    base.trainable = True
    if 0 < args.unfreeze_layers < len(base.layers):
        for layer in base.layers[: -args.unfreeze_layers]:
            layer.trainable = False
    tm._compile_model(
        model,
        args.learning_rate_finetune,
        focal_gamma=args.focal_gamma,
        focal_label_smoothing=args.focal_label_smoothing,
    )

    resumed_ckpt = args.output_dir / "best.weights.resumed.h5"
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(resumed_ckpt),
            monitor="val_top1",
            save_best_only=True,
            save_weights_only=True,
            mode="max",
        ),
        tf.keras.callbacks.EarlyStopping(
            monitor="val_top1", patience=args.patience, restore_best_weights=True, mode="max"
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_top1", factor=0.5, patience=2, min_lr=1e-6, mode="max"
        ),
    ]

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=max(1, args.epochs_finetune),
        callbacks=callbacks,
        verbose=2,
    )
    # EarlyStopping(restore_best_weights=True) leaves the best weights in memory.

    top1, top5, n = evaluate(model, samples, args.image_size, classes, limit=800)
    print(f"[verify] val n={n} top1={top1:.4f} top5={top5:.4f}")

    # ---- Export ----
    @tf.function(input_signature=[tf.TensorSpec([1, args.image_size, args.image_size, 3], tf.float32, name="image")])
    def serving(image):
        return {"probabilities": model(image, training=False)}

    concrete = serving.get_concrete_function()
    export_dir = args.output_dir / "export"
    export_dir.mkdir(parents=True, exist_ok=True)

    fconv = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    fconv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    float_model = fconv.convert()
    (export_dir / "food_classifier_float32.tflite").write_bytes(float_model)

    rep = [s for s in samples if s.split == "train"]
    random.Random(42).shuffle(rep)
    rep = rep[: max(80, args.representative_size)]

    def representative_dataset():
        for s in rep:
            x = tf.io.read_file(s.image_path)
            x = tf.image.decode_image(x, channels=3, expand_animations=False)
            x = tf.image.convert_image_dtype(x, tf.float32)
            x = tf.image.resize(x, [args.image_size, args.image_size], antialias=True)
            yield [tf.expand_dims(x, 0)]

    qconv = tf.lite.TFLiteConverter.from_concrete_functions([concrete], model)
    qconv.optimizations = [tf.lite.Optimize.DEFAULT]
    qconv.representative_dataset = representative_dataset
    qconv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    qconv.inference_input_type = tf.int8
    qconv.inference_output_type = tf.int8
    int8_model = qconv.convert()
    (export_dir / "food_classifier_int8.tflite").write_bytes(int8_model)

    labels_path = export_dir / "food_classifier_labels.csv"
    with labels_path.open("w", encoding="utf-8", newline="") as fh:
        wtr = csv.writer(fh)
        wtr.writerow(["id", "name"])
        for i, c in enumerate(classes):
            wtr.writerow([i, c])

    print(f"[ok] exported float32 + int8 to {export_dir}")

    if args.deploy:
        Path("assets/models/food_classifier.tflite").write_bytes(int8_model)
        Path("assets/models/food_classifier_labels.csv").write_text(
            labels_path.read_text(encoding="utf-8"), encoding="utf-8"
        )
        print("[ok] deployed int8 to assets/models/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
