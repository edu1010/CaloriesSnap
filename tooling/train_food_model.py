#!/usr/bin/env python3
"""Train and export a local food classifier for CalorieSnap.

Main goals of this version:
- Data curation with traceability (taxonomy normalization + filtering log).
- Robust split generation stratified by class/source.
- Stronger training pipeline (tf.data, optional mixed precision, augmentation).
- Full evaluation report (top-1, top-5, macro-F1, per-class recall, confusion summary).
- TFLite export (float32 + optional int8) ready for Flutter app inference.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import re
import sys
import traceback
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
SPLITS = ("train", "val", "test")

# For conflicting duplicates, prefer cleaner curated sources.
DEFAULT_SOURCE_PRIORITY = {
    "food101_local": 0,
    "ai4food_product": 1,
    "ai4food_subcategory": 2,
    "ai4food_category": 3,
    "nutrition5k_overhead": 4,
}

# Training should be favored so dedupe never empties train classes.
DEFAULT_SPLIT_PRIORITY = {"train": 0, "val": 1, "test": 2}

# Normalize plural/singular naming collisions found in historical runs.
CANONICAL_MERGES = {
    "beignets": "Beignet",
    "beignet": "Beignet",
    "chicken wings": "Chicken Wing",
    "chicken wing": "Chicken Wing",
    "churros": "Churro",
    "churro": "Churro",
    "crab cakes": "Crab Cake",
    "crab cake": "Crab Cake",
    "cup cakes": "Cupcake",
    "cup cake": "Cupcake",
    "cupcake": "Cupcake",
    "macarons": "Macaron",
    "macaron": "Macaron",
    "omelette": "Omelet",
    "omelet": "Omelet",
    "onion rings": "Onion Ring",
    "onion ring": "Onion Ring",
    "pancakes": "Pancake",
    "pancake": "Pancake",
    "tacos": "Taco",
    "taco": "Taco",
    "waffles": "Waffle",
    "waffle": "Waffle",
}

SPANISH_ALIAS_HINTS = {
    "Apple Pie": ["tarta de manzana"],
    "Baby Back Ribs": ["costillas"],
    "Beef Carpaccio": ["carpaccio de ternera"],
    "Beef Tartare": ["tartar de ternera"],
    "Caesar Salad": ["ensalada cesar"],
    "Caprese Salad": ["ensalada caprese"],
    "Cheesecake": ["tarta de queso"],
    "Chicken Curry": ["curry de pollo"],
    "Chicken Quesadilla": ["quesadilla de pollo"],
    "Chicken Wing": ["alitas de pollo"],
    "French Fries": ["patatas fritas", "papas fritas"],
    "French Toast": ["tostada francesa"],
    "Fried Rice": ["arroz frito"],
    "Garlic Bread": ["pan de ajo"],
    "Greek Salad": ["ensalada griega"],
    "Grilled Salmon": ["salmon a la plancha"],
    "Hamburger": ["hamburguesa"],
    "Hot Dog": ["perrito caliente"],
    "Ice Cream": ["helado"],
    "Macaroni And Cheese": ["macarrones con queso"],
    "Miso Soup": ["sopa miso"],
    "Pancake": ["tortita"],
    "Panna Cotta": ["panna cotta"],
    "Pho": ["pho"],
    "Pizza": ["pizza"],
    "Pulled Pork Sandwich": ["sandwich de cerdo desmenuzado"],
    "Ramen": ["ramen"],
    "Ravioli": ["raviolis"],
    "Risotto": ["risotto"],
    "Sashimi": ["sashimi"],
    "Spaghetti Bolognese": ["espaguetis a la bolonesa"],
    "Spaghetti Carbonara": ["espaguetis carbonara"],
    "Sushi": ["sushi"],
    "Taco": ["taco"],
    "Tiramisu": ["tiramisu"],
    "Waffle": ["gofre"],
}

BACKBONES = {
    "efficientnetv2b0",
    "mobilenetv3small",
    "mobilenetv2",
}


@dataclass(frozen=True)
class Sample:
    image_path: str
    label: str
    split: str
    source: str
    raw_label: str


@dataclass
class CurationLogRow:
    image_path: str
    source: str
    raw_label: str
    normalized_label: str
    split: str
    reason: str


def _configure_tensorflow_runtime() -> None:
    if sys.version_info >= (3, 12):
        os.environ.setdefault("WRAPT_DISABLE_EXTENSIONS", "1")


def _is_image(path: Path) -> bool:
    return path.suffix.lower() in IMAGE_EXTENSIONS


def _stable_bucket(text: str, buckets: int = 100) -> int:
    digest = hashlib.sha1(text.encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % buckets


def _split_from_hash(key: str) -> str:
    bucket = _stable_bucket(key, 100)
    if bucket < 70:
        return "train"
    if bucket < 85:
        return "val"
    return "test"


def _strip_accents(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch))


def _normalize_key(text: str) -> str:
    text = _strip_accents(text.lower())
    text = text.replace("_", " ").replace("-", " ")
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _title_label(text: str) -> str:
    return " ".join(part.capitalize() for part in _normalize_key(text).split())


def _canonicalize_label(raw_label: str) -> str:
    key = _normalize_key(raw_label)
    merged = CANONICAL_MERGES.get(key)
    if merged is not None:
        return merged
    return _title_label(raw_label)


def _load_label_map(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        return {}
    return {str(k): str(v) for k, v in raw.items()}


def _scan_food101(root: Path) -> list[Sample]:
    samples: list[Sample] = []
    images_root = root / "images"
    meta_root = root / "meta"
    has_meta_split = (meta_root / "train.txt").exists() and (meta_root / "test.txt").exists()

    if has_meta_split and images_root.exists():
        for split_file, base_split in (("train.txt", "train"), ("test.txt", "test")):
            for line in (meta_root / split_file).read_text(encoding="utf-8").splitlines():
                rel = line.strip()
                if not rel:
                    continue
                image_path = images_root / f"{rel}.jpg"
                if not image_path.exists():
                    image_path = images_root / f"{rel}.jpeg"
                if not image_path.exists():
                    continue
                raw_label = rel.split("/", 1)[0]
                split = base_split
                if base_split == "train":
                    split = "val" if _stable_bucket(rel, 10) == 0 else "train"
                samples.append(
                    Sample(
                        image_path=str(image_path.resolve()),
                        label=_canonicalize_label(raw_label),
                        split=split,
                        source="food101_local",
                        raw_label=raw_label,
                    ),
                )
        return samples

    if not images_root.exists():
        images_root = root

    for class_dir in sorted(p for p in images_root.iterdir() if p.is_dir()):
        raw_label = class_dir.name
        for img_path in class_dir.rglob("*"):
            if not img_path.is_file() or not _is_image(img_path):
                continue
            samples.append(
                Sample(
                    image_path=str(img_path.resolve()),
                    label=_canonicalize_label(raw_label),
                    split=_split_from_hash(f"food101:{img_path.name}"),
                    source="food101_local",
                    raw_label=raw_label,
                ),
            )
    return samples


def _find_images_by_name(root: Path) -> dict[str, list[Path]]:
    mapping: dict[str, list[Path]] = defaultdict(list)
    for file_path in root.rglob("*"):
        if file_path.is_file() and _is_image(file_path):
            mapping[file_path.name].append(file_path)
    return mapping


def _label_from_ai4food_id(level: str, label_id: str) -> str:
    return f"AI4Food {level.title()} {int(label_id):04d}"


def _scan_ai4food(
    dataset_root: Path,
    protocol_root: Path | None,
    level: str,
    label_map: dict[str, str],
) -> list[Sample]:
    samples: list[Sample] = []
    if protocol_root is not None:
        split_dir = protocol_root / level
        if split_dir.exists():
            image_by_name = _find_images_by_name(dataset_root)
            for split_name, split_file in (
                ("train", split_dir / "train.txt"),
                ("val", split_dir / "validation.txt"),
                ("test", split_dir / "test.txt"),
            ):
                if not split_file.exists():
                    continue
                for line in split_file.read_text(encoding="utf-8", errors="ignore").splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    parts = re.split(r"\s+", line)
                    if len(parts) < 2:
                        continue
                    file_name = parts[0].strip()
                    label_id = parts[-1].strip()
                    paths = image_by_name.get(file_name, [])
                    if not paths:
                        continue
                    raw_label = label_map.get(label_id, _label_from_ai4food_id(level, label_id))
                    samples.append(
                        Sample(
                            image_path=str(paths[0].resolve()),
                            label=_canonicalize_label(raw_label),
                            split=split_name,
                            source=f"ai4food_{level}",
                            raw_label=raw_label,
                        ),
                    )
            if samples:
                return samples

    # Fallback folder scan.
    for class_dir in sorted(p for p in dataset_root.iterdir() if p.is_dir()):
        raw_label = class_dir.name
        for img_path in class_dir.rglob("*"):
            if not img_path.is_file() or not _is_image(img_path):
                continue
            samples.append(
                Sample(
                    image_path=str(img_path.resolve()),
                    label=_canonicalize_label(raw_label),
                    split=_split_from_hash(f"ai4food:{img_path.name}"),
                    source="ai4food_folders",
                    raw_label=raw_label,
                ),
            )
    return samples


_NUTRITION5K_LABEL_RULES: list[tuple[str, tuple[str, ...]]] = [
    ("Fried Rice", ("rice", "risotto", "pilaf", "paella")),
    ("Spaghetti Carbonara", ("pasta", "noodle", "spaghetti", "macaroni")),
    ("Garlic Bread", ("bread", "toast", "bun", "bagel", "roll")),
    ("Omelet", ("egg", "omelet", "omelette", "frittata")),
    ("Caesar Salad", ("salad", "lettuce", "greens", "slaw")),
    ("Chicken Curry", ("chicken", "poultry", "turkey")),
    ("Steak", ("beef", "steak")),
    ("Pork Chop", ("pork", "ham", "bacon")),
    ("Sashimi", ("fish", "salmon", "tuna", "cod", "shrimp")),
    ("French Fries", ("potato", "fries", "chips")),
    ("Miso Soup", ("soup", "broth", "chowder")),
    ("Fruit Mixed", ("fruit", "apple", "banana", "orange", "berry", "grape")),
]


def _map_nutrition5k_ingredient_to_label(ingredient_name: str) -> str | None:
    text = ingredient_name.lower()
    for label, keywords in _NUTRITION5K_LABEL_RULES:
        if any(keyword in text for keyword in keywords):
            return label
    return None


def _pick_nutrition5k_rgb_image(dish_dir: Path) -> Path | None:
    if not dish_dir.exists():
        return None
    candidates = [
        p
        for p in dish_dir.iterdir()
        if p.is_file() and _is_image(p) and "depth" not in p.stem.lower()
    ]
    if not candidates:
        return None
    rgb_candidates = [p for p in candidates if "rgb" in p.stem.lower()]
    chosen = sorted(rgb_candidates or candidates)
    return chosen[0]


def _scan_nutrition5k(root: Path) -> list[Sample]:
    samples: list[Sample] = []
    metadata_dir = root / "metadata"
    imagery_dir = root / "imagery" / "realsense_overhead"
    if not metadata_dir.exists() or not imagery_dir.exists():
        return samples

    metadata_files = [
        metadata_dir / "dish_metadata_cafe1.csv",
        metadata_dir / "dish_metadata_cafe2.csv",
    ]
    for csv_path in metadata_files:
        if not csv_path.exists():
            continue
        with csv_path.open("r", encoding="utf-8", errors="ignore", newline="") as f:
            reader = csv.reader(f)
            first_row = next(reader, None)
            if not first_row:
                continue

            rows: list[list[str]]
            if first_row[0].startswith("dish_"):
                rows = [first_row, *list(reader)]
            else:
                rows = list(reader)

            for row in rows:
                if len(row) < 9:
                    continue
                dish_id = row[0].strip()
                if not dish_id:
                    continue

                best_name = None
                best_grams = -1.0
                for base in range(6, len(row), 7):
                    if base + 2 >= len(row):
                        break
                    ingr_name = row[base + 1].strip()
                    if not ingr_name:
                        continue
                    try:
                        grams = float(row[base + 2])
                    except ValueError:
                        grams = 0.0
                    if grams > best_grams:
                        best_grams = grams
                        best_name = ingr_name

                if not best_name:
                    continue
                mapped_label = _map_nutrition5k_ingredient_to_label(best_name)
                if mapped_label is None:
                    continue

                rgb_path = _pick_nutrition5k_rgb_image(imagery_dir / dish_id)
                if rgb_path is None:
                    continue

                samples.append(
                    Sample(
                        image_path=str(rgb_path.resolve()),
                        label=_canonicalize_label(mapped_label),
                        split=_split_from_hash(f"nutrition5k:{dish_id}"),
                        source="nutrition5k_overhead",
                        raw_label=best_name,
                    ),
                )
    return samples


def _fast_image_fingerprint(image_path: str, hash_bytes: int) -> str | None:
    try:
        path = Path(image_path)
        stat = path.stat()
        size = stat.st_size
        with path.open("rb") as f:
            head = f.read(hash_bytes)
            tail = b""
            if size > hash_bytes:
                f.seek(max(0, size - hash_bytes))
                tail = f.read(hash_bytes)
        digest = hashlib.sha1()
        digest.update(str(size).encode("utf-8"))
        digest.update(head)
        digest.update(tail)
        return digest.hexdigest()
    except OSError:
        return None


def _sample_priority(sample: Sample) -> tuple[int, int]:
    split_rank = DEFAULT_SPLIT_PRIORITY.get(sample.split, 99)
    source_rank = DEFAULT_SOURCE_PRIORITY.get(sample.source, 99)
    return split_rank, source_rank


def _deduplicate_samples(
    samples: list[Sample],
    hash_bytes: int,
) -> tuple[list[Sample], dict[str, int], list[CurationLogRow]]:
    by_fingerprint: dict[str, Sample] = {}
    stats = {
        "dedupe_candidates": 0,
        "dedupe_removed": 0,
        "dedupe_conflicting_label_removed": 0,
        "dedupe_io_errors": 0,
    }
    dropped: list[CurationLogRow] = []

    for sample in samples:
        fingerprint = _fast_image_fingerprint(sample.image_path, hash_bytes)
        if fingerprint is None:
            stats["dedupe_io_errors"] += 1
            fingerprint = f"path:{sample.image_path}"

        previous = by_fingerprint.get(fingerprint)
        if previous is None:
            by_fingerprint[fingerprint] = sample
            continue

        stats["dedupe_candidates"] += 1
        prev_rank = _sample_priority(previous)
        new_rank = _sample_priority(sample)

        keep_new = new_rank < prev_rank
        if prev_rank == new_rank and previous.label != sample.label:
            keep_new = DEFAULT_SOURCE_PRIORITY.get(sample.source, 99) < DEFAULT_SOURCE_PRIORITY.get(
                previous.source,
                99,
            )

        if keep_new:
            dropped.append(
                CurationLogRow(
                    image_path=previous.image_path,
                    source=previous.source,
                    raw_label=previous.raw_label,
                    normalized_label=previous.label,
                    split=previous.split,
                    reason="dedupe_replaced",
                ),
            )
            by_fingerprint[fingerprint] = sample
            stats["dedupe_removed"] += 1
            if previous.label != sample.label:
                stats["dedupe_conflicting_label_removed"] += 1
        else:
            dropped.append(
                CurationLogRow(
                    image_path=sample.image_path,
                    source=sample.source,
                    raw_label=sample.raw_label,
                    normalized_label=sample.label,
                    split=sample.split,
                    reason="dedupe_removed",
                ),
            )
            stats["dedupe_removed"] += 1
            if previous.label != sample.label:
                stats["dedupe_conflicting_label_removed"] += 1

    deduped = list(by_fingerprint.values())
    return deduped, stats, dropped


def _allocate_split_counts(n: int, train_ratio: float, val_ratio: float) -> tuple[int, int, int]:
    if n <= 0:
        return 0, 0, 0
    if n == 1:
        return 1, 0, 0
    if n == 2:
        return 1, 1, 0

    n_train = int(round(n * train_ratio))
    n_val = int(round(n * val_ratio))
    n_test = n - n_train - n_val

    if n_val <= 0:
        n_val = 1
        n_train -= 1
    if n_test <= 0:
        n_test = 1
        n_train -= 1

    if n_train <= 0:
        n_train = 1
        if n_val > n_test:
            n_val -= 1
        else:
            n_test -= 1

    while n_train + n_val + n_test > n:
        if n_train >= n_val and n_train >= n_test and n_train > 1:
            n_train -= 1
        elif n_val >= n_test and n_val > 1:
            n_val -= 1
        elif n_test > 1:
            n_test -= 1
        else:
            break

    while n_train + n_val + n_test < n:
        n_train += 1

    return n_train, n_val, n_test


def _rebalance_splits(
    samples: list[Sample],
    random_seed: int,
    train_ratio: float,
    val_ratio: float,
) -> list[Sample]:
    rnd = random.Random(random_seed)
    grouped: dict[tuple[str, str], list[Sample]] = defaultdict(list)
    for sample in samples:
        grouped[(sample.label, sample.source)].append(sample)

    out: list[Sample] = []
    for (_, _), rows in grouped.items():
        rows_copy = rows[:]
        rnd.shuffle(rows_copy)
        n_train, n_val, n_test = _allocate_split_counts(
            len(rows_copy),
            train_ratio=train_ratio,
            val_ratio=val_ratio,
        )
        for idx, row in enumerate(rows_copy):
            if idx < n_train:
                split = "train"
            elif idx < n_train + n_val:
                split = "val"
            else:
                split = "test"
            out.append(
                Sample(
                    image_path=row.image_path,
                    label=row.label,
                    split=split,
                    source=row.source,
                    raw_label=row.raw_label,
                ),
            )
    return out


def _filter_and_curate_samples(
    samples: list[Sample],
    target_classes: set[str],
    min_file_size_bytes: int,
) -> tuple[list[Sample], list[CurationLogRow], dict[str, int]]:
    curated: list[Sample] = []
    dropped: list[CurationLogRow] = []
    reason_counts: Counter[str] = Counter()

    for sample in samples:
        p = Path(sample.image_path)
        if not p.exists():
            reason = "missing_file"
            dropped.append(
                CurationLogRow(
                    image_path=sample.image_path,
                    source=sample.source,
                    raw_label=sample.raw_label,
                    normalized_label=sample.label,
                    split=sample.split,
                    reason=reason,
                ),
            )
            reason_counts[reason] += 1
            continue

        try:
            if p.stat().st_size < min_file_size_bytes:
                reason = "tiny_file"
                dropped.append(
                    CurationLogRow(
                        image_path=sample.image_path,
                        source=sample.source,
                        raw_label=sample.raw_label,
                        normalized_label=sample.label,
                        split=sample.split,
                        reason=reason,
                    ),
                )
                reason_counts[reason] += 1
                continue
        except OSError:
            reason = "stat_error"
            dropped.append(
                CurationLogRow(
                    image_path=sample.image_path,
                    source=sample.source,
                    raw_label=sample.raw_label,
                    normalized_label=sample.label,
                    split=sample.split,
                    reason=reason,
                ),
            )
            reason_counts[reason] += 1
            continue

        if sample.source.startswith("ai4food"):
            base_name = Path(sample.image_path).name
            # Keep only AI4Food entries aligned with Food101-like objective.
            if "_Food101_" not in base_name and sample.label not in target_classes:
                reason = "ai4food_domain_filtered"
                dropped.append(
                    CurationLogRow(
                        image_path=sample.image_path,
                        source=sample.source,
                        raw_label=sample.raw_label,
                        normalized_label=sample.label,
                        split=sample.split,
                        reason=reason,
                    ),
                )
                reason_counts[reason] += 1
                continue

        if sample.label not in target_classes:
            reason = "outside_target_taxonomy"
            dropped.append(
                CurationLogRow(
                    image_path=sample.image_path,
                    source=sample.source,
                    raw_label=sample.raw_label,
                    normalized_label=sample.label,
                    split=sample.split,
                    reason=reason,
                ),
            )
            reason_counts[reason] += 1
            continue

        curated.append(sample)

    return curated, dropped, dict(reason_counts)


def _cap_samples_per_class(
    samples: list[Sample],
    max_per_class: int | None,
    random_seed: int,
) -> list[Sample]:
    if max_per_class is None or max_per_class <= 0:
        return samples
    rnd = random.Random(random_seed)
    grouped: dict[str, list[Sample]] = defaultdict(list)
    for sample in samples:
        grouped[sample.label].append(sample)

    capped: list[Sample] = []
    for _, rows in grouped.items():
        if len(rows) <= max_per_class:
            capped.extend(rows)
            continue
        rows_copy = rows[:]
        rnd.shuffle(rows_copy)
        capped.extend(rows_copy[:max_per_class])
    return capped


def _filter_classes(samples: list[Sample], min_count: int) -> tuple[list[Sample], set[str]]:
    counts = Counter(sample.label for sample in samples)
    valid = {label for label, count in counts.items() if count >= min_count}
    return [sample for sample in samples if sample.label in valid], valid


def _write_manifest(samples: list[Sample], out_dir: Path) -> tuple[Path, list[str]]:
    out_dir.mkdir(parents=True, exist_ok=True)
    classes = sorted({sample.label for sample in samples})
    class_path = out_dir / "classes.txt"
    class_path.write_text("\n".join(classes) + "\n", encoding="utf-8")

    manifest_path = out_dir / "manifest.jsonl"
    with manifest_path.open("w", encoding="utf-8") as f:
        for sample in samples:
            f.write(
                json.dumps(
                    {
                        "image_path": sample.image_path,
                        "label": sample.label,
                        "split": sample.split,
                        "source": sample.source,
                        "raw_label": sample.raw_label,
                    },
                    ensure_ascii=False,
                )
                + "\n",
            )
    return manifest_path, classes


def _write_curation_log(out_dir: Path, rows: list[CurationLogRow]) -> None:
    path = out_dir / "curation_log.csv"
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["image_path", "source", "raw_label", "normalized_label", "split", "reason"])
        for row in rows:
            writer.writerow(
                [
                    row.image_path,
                    row.source,
                    row.raw_label,
                    row.normalized_label,
                    row.split,
                    row.reason,
                ],
            )


def _build_taxonomy_summary(samples: list[Sample], classes: list[str]) -> list[dict[str, object]]:
    aliases_en: dict[str, set[str]] = defaultdict(set)
    for sample in samples:
        aliases_en[sample.label].add(sample.raw_label)
        aliases_en[sample.label].add(sample.label)

    taxonomy: list[dict[str, object]] = []
    for class_name in classes:
        en_aliases = sorted({_title_label(alias) for alias in aliases_en.get(class_name, set()) if alias})
        es_aliases = sorted({
            _title_label(alias)
            for alias in SPANISH_ALIAS_HINTS.get(class_name, [])
        })
        taxonomy.append(
            {
                "canonical": class_name,
                "aliases_en": en_aliases,
                "aliases_es": es_aliases,
            },
        )
    return taxonomy


def _write_summary(
    samples: list[Sample],
    classes: list[str],
    out_dir: Path,
    dedupe_stats: dict[str, int],
    drop_reason_counts: dict[str, int],
) -> None:
    split_counts = Counter(sample.split for sample in samples)
    source_counts = Counter(sample.source for sample in samples)
    class_counts = Counter(sample.label for sample in samples)

    per_class_split: dict[str, dict[str, int]] = {}
    empty_train: list[str] = []
    empty_val: list[str] = []
    empty_test: list[str] = []
    by_class: dict[str, list[Sample]] = defaultdict(list)
    for sample in samples:
        by_class[sample.label].append(sample)

    for class_name in classes:
        splits = {s: 0 for s in SPLITS}
        for sample in by_class.get(class_name, []):
            splits[sample.split] += 1
        per_class_split[class_name] = splits
        if splits["train"] == 0:
            empty_train.append(class_name)
        if splits["val"] == 0:
            empty_val.append(class_name)
        if splits["test"] == 0:
            empty_test.append(class_name)

    summary = {
        "num_samples": len(samples),
        "num_classes": len(classes),
        "split_counts": dict(split_counts),
        "source_counts": dict(source_counts),
        "top_classes": class_counts.most_common(30),
        "tail_classes": sorted(class_counts.items(), key=lambda kv: kv[1])[:30],
        "dedupe_stats": dedupe_stats,
        "drop_reason_counts": drop_reason_counts,
        "class_split_coverage": {
            "classes_missing_train": empty_train,
            "classes_missing_val": empty_val,
            "classes_missing_test": empty_test,
            "per_class_split": per_class_split,
        },
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _write_audit_report(
    out_dir: Path,
    baseline_report_path: Path | None,
    baseline_manifest_path: Path | None,
) -> None:
    report: dict[str, object] = {}
    if baseline_report_path is not None and baseline_report_path.exists():
        try:
            report["baseline_training_report"] = json.loads(
                baseline_report_path.read_text(encoding="utf-8"),
            )
        except json.JSONDecodeError:
            report["baseline_training_report"] = {"error": "invalid_json"}

    if baseline_manifest_path is not None and baseline_manifest_path.exists():
        rows = [
            json.loads(line)
            for line in baseline_manifest_path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        report["baseline_manifest_stats"] = {
            "num_samples": len(rows),
            "num_classes": len({row["label"] for row in rows}),
            "split_counts": dict(Counter(row["split"] for row in rows)),
            "source_counts": dict(Counter(row.get("source", "unknown") for row in rows)),
        }

    (out_dir / "audit_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _read_manifest(path: Path) -> list[Sample]:
    rows: list[Sample] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        obj = json.loads(line)
        rows.append(
            Sample(
                image_path=str(obj["image_path"]),
                label=str(obj["label"]),
                split=str(obj["split"]),
                source=str(obj.get("source", "unknown")),
                raw_label=str(obj.get("raw_label", obj["label"])),
            ),
        )
    return rows


def _set_mixed_precision_if_supported(enable: bool) -> str:
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    if not enable:
        return "float32"

    # DirectML plugin (Windows native) reports a GPU device but usually does not
    # benefit from mixed_float16 the same way CUDA does.
    tf_site = Path(tf.__file__).resolve().parent.parent
    directml_plugin_dir = tf_site / "tensorflow-plugins" / "directml"
    if directml_plugin_dir.exists():
        tf.keras.mixed_precision.set_global_policy("float32")
        return "float32"

    gpus = tf.config.list_physical_devices("GPU")
    if gpus:
        tf.keras.mixed_precision.set_global_policy("mixed_float16")
        return "mixed_float16"

    tf.keras.mixed_precision.set_global_policy("float32")
    return "float32"


def _build_tf_datasets(
    samples: list[Sample],
    classes: list[str],
    image_size: int,
    batch_size: int,
    balance_classes: bool,
    class_weight_max: float,
    mixup_alpha: float,
    cutmix_alpha: float,
    cutmix_prob: float,
    cache_train: bool,
    cache_dir: Path,
):
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    class_to_index = {name: idx for idx, name in enumerate(classes)}

    def split_subset(split: str) -> tuple[list[str], list[int]]:
        paths: list[str] = []
        labels: list[int] = []
        for row in samples:
            if row.split != split:
                continue
            paths.append(row.image_path)
            labels.append(class_to_index[row.label])
        return paths, labels

    def decode_and_resize(path):
        img = tf.io.read_file(path)
        img = tf.image.decode_image(img, channels=3, expand_animations=False)
        img = tf.image.convert_image_dtype(img, tf.float32)  # [0, 1]
        img = tf.image.resize(img, [image_size, image_size], antialias=True)
        return img

    def augment(img):
        img = tf.image.random_flip_left_right(img)
        img = tf.image.random_brightness(img, max_delta=0.14)
        img = tf.image.random_contrast(img, lower=0.8, upper=1.2)
        img = tf.image.random_saturation(img, lower=0.82, upper=1.18)
        return tf.clip_by_value(img, 0.0, 1.0)

    def make_dataset(paths: list[str], labels: list[int], training: bool):
        ds = tf.data.Dataset.from_tensor_slices((paths, labels))
        if training:
            ds = ds.shuffle(min(len(paths), 20000), reshuffle_each_iteration=True)

        def _load(path, label):
            img = decode_and_resize(path)
            if training:
                img = augment(img)
            label_one_hot = tf.one_hot(label, depth=len(classes))
            return img, label_one_hot

        ds = ds.map(_load, num_parallel_calls=tf.data.AUTOTUNE)
        if training and cache_train:
            cache_dir.mkdir(parents=True, exist_ok=True)
            ds = ds.cache(str((cache_dir / "train.cache").resolve()))
        if not training:
            ds = ds.cache()
        ds = ds.batch(batch_size, drop_remainder=False)
        ds = ds.prefetch(tf.data.AUTOTUNE)
        return ds

    train_paths, train_labels = split_subset("train")
    val_paths, val_labels = split_subset("val")
    test_paths, test_labels = split_subset("test")

    if not train_paths or not val_paths:
        raise RuntimeError("Manifest must contain at least train and val samples.")

    train_counts = Counter(train_labels)
    if balance_classes:
        total = float(len(train_labels))
        num_classes = float(len(classes))
        class_weights = []
        for idx in range(len(classes)):
            count = float(train_counts.get(idx, 0))
            if count <= 0:
                class_weights.append(class_weight_max)
                continue
            raw_weight = total / (num_classes * count)
            class_weights.append(float(min(class_weight_max, max(0.05, raw_weight))))
    else:
        class_weights = [1.0 for _ in classes]
    class_weights_tensor = tf.constant(class_weights, dtype=tf.float32)

    def _add_sample_weight(image, label):
        label_index = tf.argmax(label, axis=-1, output_type=tf.int32)
        sample_weight = tf.gather(class_weights_tensor, label_index)
        return image, label, sample_weight

    def _sample_beta_distribution(batch_size_tensor, alpha):
        shape = tf.stack([batch_size_tensor])
        if alpha <= 0.0:
            return tf.ones(shape, dtype=tf.float32)
        gamma_1 = tf.random.gamma(shape=shape, alpha=alpha, dtype=tf.float32)
        gamma_2 = tf.random.gamma(shape=shape, alpha=alpha, dtype=tf.float32)
        return gamma_1 / (gamma_1 + gamma_2)

    def _apply_mixup(images, labels, sample_weights):
        if mixup_alpha <= 0.0:
            return images, labels, sample_weights
        batch_count = tf.shape(images)[0]
        indices = tf.random.shuffle(tf.range(batch_count))
        mixed_images = tf.gather(images, indices)
        mixed_labels = tf.gather(labels, indices)
        mixed_weights = tf.gather(sample_weights, indices)
        lam = _sample_beta_distribution(batch_count, mixup_alpha)
        lam_images = tf.reshape(lam, [-1, 1, 1, 1])
        lam_labels = tf.reshape(lam, [-1, 1])
        images = images * lam_images + mixed_images * (1.0 - lam_images)
        labels = labels * lam_labels + mixed_labels * (1.0 - lam_labels)
        sample_weights = sample_weights * lam + mixed_weights * (1.0 - lam)
        return images, labels, sample_weights

    def _apply_cutmix(images, labels, sample_weights):
        if cutmix_alpha <= 0.0:
            return images, labels, sample_weights

        batch_count = tf.shape(images)[0]
        indices = tf.random.shuffle(tf.range(batch_count))
        paired_images = tf.gather(images, indices)
        paired_labels = tf.gather(labels, indices)
        paired_weights = tf.gather(sample_weights, indices)

        height = tf.shape(images)[1]
        width = tf.shape(images)[2]

        lam = _sample_beta_distribution(1, cutmix_alpha)[0]
        cut_ratio = tf.sqrt(1.0 - lam)
        cut_w = tf.cast(tf.cast(width, tf.float32) * cut_ratio, tf.int32)
        cut_h = tf.cast(tf.cast(height, tf.float32) * cut_ratio, tf.int32)

        center_x = tf.random.uniform([], minval=0, maxval=width, dtype=tf.int32)
        center_y = tf.random.uniform([], minval=0, maxval=height, dtype=tf.int32)

        x1 = tf.clip_by_value(center_x - cut_w // 2, 0, width)
        y1 = tf.clip_by_value(center_y - cut_h // 2, 0, height)
        x2 = tf.clip_by_value(center_x + cut_w // 2, 0, width)
        y2 = tf.clip_by_value(center_y + cut_h // 2, 0, height)

        yy = tf.range(height)[:, tf.newaxis]
        xx = tf.range(width)[tf.newaxis, :]
        box_mask = tf.logical_and(
            tf.logical_and(yy >= y1, yy < y2),
            tf.logical_and(xx >= x1, xx < x2),
        )
        box_mask = tf.cast(box_mask, tf.float32)[tf.newaxis, :, :, tf.newaxis]
        box_mask = tf.tile(box_mask, [batch_count, 1, 1, 1])

        images = images * (1.0 - box_mask) + paired_images * box_mask
        patch_area = tf.cast((x2 - x1) * (y2 - y1), tf.float32)
        full_area = tf.cast(width * height, tf.float32)
        lam_adjusted = 1.0 - patch_area / tf.maximum(full_area, 1.0)

        labels = labels * lam_adjusted + paired_labels * (1.0 - lam_adjusted)
        sample_weights = sample_weights * lam_adjusted + paired_weights * (1.0 - lam_adjusted)
        return images, labels, sample_weights

    def _apply_batch_mixing(images, labels, sample_weights):
        if mixup_alpha <= 0.0 and cutmix_alpha <= 0.0:
            return images, labels, sample_weights
        if mixup_alpha <= 0.0:
            return _apply_cutmix(images, labels, sample_weights)
        if cutmix_alpha <= 0.0:
            return _apply_mixup(images, labels, sample_weights)
        do_cutmix = tf.random.uniform([], dtype=tf.float32) < cutmix_prob
        return tf.cond(
            do_cutmix,
            lambda: _apply_cutmix(images, labels, sample_weights),
            lambda: _apply_mixup(images, labels, sample_weights),
        )

    train_ds = make_dataset(train_paths, train_labels, training=True)
    train_ds = train_ds.map(_add_sample_weight, num_parallel_calls=tf.data.AUTOTUNE)
    train_ds = train_ds.map(_apply_batch_mixing, num_parallel_calls=tf.data.AUTOTUNE)

    val_ds = make_dataset(val_paths, val_labels, training=False)
    test_ds = make_dataset(test_paths, test_labels, training=False) if test_paths else None

    eval_val_ds = val_ds
    eval_test_ds = test_ds
    return train_ds, val_ds, test_ds, eval_val_ds, eval_test_ds


def _build_model(num_classes: int, image_size: int, backbone: str, dropout: float):
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    backbone = backbone.lower().strip()
    if backbone not in BACKBONES:
        raise ValueError(f"Unsupported backbone: {backbone}")

    try:
        if backbone == "efficientnetv2b0":
            base = tf.keras.applications.EfficientNetV2B0(
                include_top=False,
                weights="imagenet",
                include_preprocessing=False,
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )
        elif backbone == "mobilenetv3small":
            base = tf.keras.applications.MobileNetV3Small(
                include_top=False,
                weights="imagenet",
                include_preprocessing=False,
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )
        else:
            base = tf.keras.applications.MobileNetV2(
                include_top=False,
                weights="imagenet",
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )
    except Exception:  # noqa: BLE001
        print("[warn] Could not load ImageNet weights; using random initialization.")
        if backbone == "efficientnetv2b0":
            base = tf.keras.applications.EfficientNetV2B0(
                include_top=False,
                weights=None,
                include_preprocessing=False,
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )
        elif backbone == "mobilenetv3small":
            base = tf.keras.applications.MobileNetV3Small(
                include_top=False,
                weights=None,
                include_preprocessing=False,
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )
        else:
            base = tf.keras.applications.MobileNetV2(
                include_top=False,
                weights=None,
                input_shape=(image_size, image_size, 3),
                pooling="avg",
            )

    base.trainable = False

    inputs = tf.keras.Input(shape=(image_size, image_size, 3), name="image")
    # Flutter sends float pixels in [0, 1]. Backbones without preprocessing expect [-1, 1].
    x = tf.keras.layers.Rescaling(scale=2.0, offset=-1.0, name="to_minus_one_one")(inputs)
    x = base(x, training=False)
    x = tf.keras.layers.Dropout(dropout)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax", dtype="float32")(x)
    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    return model, base


def _categorical_focal_loss(gamma: float, label_smoothing: float):
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    epsilon = tf.keras.backend.epsilon()

    def loss_fn(y_true, y_pred):
        y_true = tf.cast(y_true, tf.float32)
        y_pred = tf.cast(y_pred, tf.float32)
        num_classes = tf.cast(tf.shape(y_true)[-1], tf.float32)
        if label_smoothing > 0.0:
            y_true = y_true * (1.0 - label_smoothing) + label_smoothing / num_classes
        y_pred = tf.clip_by_value(y_pred, epsilon, 1.0 - epsilon)
        cross_entropy = -y_true * tf.math.log(y_pred)
        modulating = tf.pow(1.0 - y_pred, gamma)
        loss = tf.reduce_sum(modulating * cross_entropy, axis=-1)
        return loss

    return loss_fn


def _compile_model(model, lr: float, focal_gamma: float, focal_label_smoothing: float):
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    if focal_gamma > 0.0:
        loss = _categorical_focal_loss(
            gamma=focal_gamma,
            label_smoothing=focal_label_smoothing,
        )
    else:
        loss = tf.keras.losses.CategoricalCrossentropy(label_smoothing=focal_label_smoothing)

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=lr),
        loss=loss,
        metrics=[
            tf.keras.metrics.CategoricalAccuracy(name="top1"),
            tf.keras.metrics.TopKCategoricalAccuracy(k=5, name="top5"),
        ],
    )


def _collect_predictions(model, ds):
    y_true_batches = []
    y_prob_batches = []
    for images, labels in ds:
        probs = model.predict(images, verbose=0)
        y_true_batches.append(labels.numpy())
        y_prob_batches.append(probs)

    if not y_true_batches:
        return np.empty((0,), dtype=np.int64), np.empty((0, 0), dtype=np.float32)

    y_true = np.concatenate(y_true_batches, axis=0)
    y_true_idx = np.argmax(y_true, axis=1)
    y_prob = np.concatenate(y_prob_batches, axis=0)
    return y_true_idx, y_prob


def _metrics_from_predictions(y_true: np.ndarray, y_prob: np.ndarray, classes: list[str]) -> dict[str, object]:
    if y_true.size == 0 or y_prob.size == 0:
        return {
            "top1": 0.0,
            "top5": 0.0,
            "macro_f1": 0.0,
            "per_class_recall": {},
            "confusion_top_errors": [],
        }

    num_classes = len(classes)
    y_pred = np.argmax(y_prob, axis=1)
    top1 = float(np.mean(y_pred == y_true))

    k = min(5, y_prob.shape[1])
    topk_idx = np.argpartition(y_prob, -k, axis=1)[:, -k:]
    top5 = float(np.mean([int(t in row) for t, row in zip(y_true.tolist(), topk_idx.tolist())]))

    cm = np.zeros((num_classes, num_classes), dtype=np.int64)
    for t, p in zip(y_true.tolist(), y_pred.tolist()):
        if 0 <= t < num_classes and 0 <= p < num_classes:
            cm[t, p] += 1

    recalls: dict[str, float] = {}
    f1_scores = []
    for idx, class_name in enumerate(classes):
        tp = cm[idx, idx]
        fp = cm[:, idx].sum() - tp
        fn = cm[idx, :].sum() - tp
        precision = float(tp / (tp + fp)) if (tp + fp) > 0 else 0.0
        recall = float(tp / (tp + fn)) if (tp + fn) > 0 else 0.0
        f1 = (2.0 * precision * recall / (precision + recall)) if (precision + recall) > 0.0 else 0.0
        f1_scores.append(f1)
        recalls[class_name] = recall

    macro_f1 = float(np.mean(f1_scores)) if f1_scores else 0.0

    error_pairs = []
    for i in range(num_classes):
        for j in range(num_classes):
            if i == j:
                continue
            count = int(cm[i, j])
            if count <= 0:
                continue
            error_pairs.append((count, classes[i], classes[j]))
    error_pairs.sort(reverse=True)

    confusion_top_errors = [
        {
            "true": true_name,
            "pred": pred_name,
            "count": count,
        }
        for count, true_name, pred_name in error_pairs[:25]
    ]

    return {
        "top1": top1,
        "top5": top5,
        "macro_f1": macro_f1,
        "per_class_recall": recalls,
        "confusion_top_errors": confusion_top_errors,
    }


def _train_and_export(
    samples: list[Sample],
    classes: list[str],
    out_dir: Path,
    image_size: int,
    batch_size: int,
    epochs_head: int,
    epochs_finetune: int,
    learning_rate_head: float,
    learning_rate_finetune: float,
    focal_gamma: float,
    focal_label_smoothing: float,
    balance_classes: bool,
    class_weight_max: float,
    mixup_alpha: float,
    cutmix_alpha: float,
    cutmix_prob: float,
    quantize_int8: bool,
    representative_size: int,
    deploy_assets: bool,
    backbone: str,
    dropout: float,
    unfreeze_layers: int,
    enable_mixed_precision: bool,
    cache_train: bool,
    skip_tflite_export: bool,
):
    _configure_tensorflow_runtime()
    import tensorflow as tf  # type: ignore

    mp_policy = _set_mixed_precision_if_supported(enable_mixed_precision)

    (
        train_ds,
        val_ds,
        test_ds,
        eval_val_ds,
        eval_test_ds,
    ) = _build_tf_datasets(
        samples,
        classes,
        image_size,
        batch_size,
        balance_classes=balance_classes,
        class_weight_max=class_weight_max,
        mixup_alpha=mixup_alpha,
        cutmix_alpha=cutmix_alpha,
        cutmix_prob=cutmix_prob,
        cache_train=cache_train,
        cache_dir=out_dir / "tf_cache",
    )

    model, base = _build_model(
        num_classes=len(classes),
        image_size=image_size,
        backbone=backbone,
        dropout=dropout,
    )
    _compile_model(
        model,
        learning_rate_head,
        focal_gamma=focal_gamma,
        focal_label_smoothing=focal_label_smoothing,
    )

    checkpoint_path = out_dir / "best.weights.h5"
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(checkpoint_path),
            monitor="val_top1",
            save_best_only=True,
            save_weights_only=True,
            mode="max",
        ),
        tf.keras.callbacks.EarlyStopping(
            monitor="val_top1",
            patience=4,
            restore_best_weights=True,
            mode="max",
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_top1",
            factor=0.5,
            patience=2,
            min_lr=1e-6,
            mode="max",
        ),
    ]

    history_head = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=max(1, epochs_head),
        callbacks=callbacks,
        verbose=2,
    )

    if epochs_finetune > 0:
        base.trainable = True
        if unfreeze_layers > 0 and unfreeze_layers < len(base.layers):
            for layer in base.layers[:-unfreeze_layers]:
                layer.trainable = False
        _compile_model(
            model,
            learning_rate_finetune,
            focal_gamma=focal_gamma,
            focal_label_smoothing=focal_label_smoothing,
        )
        history_ft = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=max(1, epochs_finetune),
            callbacks=callbacks,
            verbose=2,
        )
    else:
        history_ft = None

    if checkpoint_path.exists():
        model.load_weights(str(checkpoint_path))

    val_eval = model.evaluate(eval_val_ds, verbose=0, return_dict=True)
    if eval_test_ds is not None:
        test_eval = model.evaluate(eval_test_ds, verbose=0, return_dict=True)
    else:
        test_eval = None

    y_true_val, y_prob_val = _collect_predictions(model, eval_val_ds)
    val_metrics_extra = _metrics_from_predictions(y_true_val, y_prob_val, classes)

    if eval_test_ds is not None:
        y_true_test, y_prob_test = _collect_predictions(model, eval_test_ds)
        test_metrics_extra = _metrics_from_predictions(y_true_test, y_prob_test, classes)
    else:
        test_metrics_extra = None

    report = {
        "backbone": backbone,
        "mixed_precision_policy": mp_policy,
        "val_eval": {k: float(v) for k, v in val_eval.items()},
        "test_eval": {k: float(v) for k, v in test_eval.items()} if test_eval else None,
        "val_metrics": val_metrics_extra,
        "test_metrics": test_metrics_extra,
        "head_epochs": len(history_head.history.get("loss", [])),
        "finetune_epochs": len(history_ft.history.get("loss", [])) if history_ft else 0,
        "train_config": {
            "image_size": image_size,
            "batch_size": batch_size,
            "focal_gamma": focal_gamma,
            "focal_label_smoothing": focal_label_smoothing,
            "balance_classes": balance_classes,
            "class_weight_max": class_weight_max,
            "mixup_alpha": mixup_alpha,
            "cutmix_alpha": cutmix_alpha,
            "cutmix_prob": cutmix_prob,
            "dropout": dropout,
            "unfreeze_layers": unfreeze_layers,
        },
    }

    (out_dir / "training_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    labels_csv = out_dir / "food_classifier_labels.csv"
    with labels_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name"])
        for idx, class_name in enumerate(classes):
            writer.writerow([idx, class_name])

    if skip_tflite_export:
        print("[info] Skipping TFLite export by request (--skip-tflite-export).")
        return

    @tf.function(
        input_signature=[
            tf.TensorSpec(
                shape=[1, image_size, image_size, 3],
                dtype=tf.float32,
                name="image",
            ),
        ],
    )
    def _serving_fn(image):
        return {"probabilities": model(image, training=False)}

    concrete_fn = _serving_fn.get_concrete_function()

    def _convert_float_tflite():
        try:
            converter_local = tf.lite.TFLiteConverter.from_concrete_functions([concrete_fn], model)
            converter_local.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
            return converter_local.convert()
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] Concrete-function conversion failed ({exc}); retrying from keras model.")
            converter_local = tf.lite.TFLiteConverter.from_keras_model(model)
            converter_local.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
            return converter_local.convert()

    float_tflite_path = out_dir / "food_classifier_float32.tflite"
    float_tflite = _convert_float_tflite()
    float_tflite_path.write_bytes(float_tflite)

    if quantize_int8:
        rep_candidates = [s for s in samples if s.split == "train"]
        random.Random(42).shuffle(rep_candidates)
        rep_subset = rep_candidates[: max(80, representative_size)]

        def representative_dataset():
            for sample in rep_subset:
                img = tf.io.read_file(sample.image_path)
                img = tf.image.decode_image(img, channels=3, expand_animations=False)
                img = tf.image.convert_image_dtype(img, tf.float32)
                img = tf.image.resize(img, [image_size, image_size], antialias=True)
                img = tf.expand_dims(img, axis=0)
                yield [img]

        try:
            converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_fn], model)
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.representative_dataset = representative_dataset
            converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
            converter.inference_input_type = tf.int8
            converter.inference_output_type = tf.int8
            int8_model = converter.convert()
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] INT8 concrete conversion failed ({exc}); retrying from keras model.")
            converter = tf.lite.TFLiteConverter.from_keras_model(model)
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.representative_dataset = representative_dataset
            converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
            converter.inference_input_type = tf.int8
            converter.inference_output_type = tf.int8
            int8_model = converter.convert()
        (out_dir / "food_classifier_int8.tflite").write_bytes(int8_model)

    if deploy_assets:
        app_model_path = Path("assets/models/food_classifier.tflite")
        app_labels_path = Path("assets/models/food_classifier_labels.csv")
        if (out_dir / "food_classifier_int8.tflite").exists():
            app_model_path.write_bytes((out_dir / "food_classifier_int8.tflite").read_bytes())
        else:
            app_model_path.write_bytes(float_tflite_path.read_bytes())
        app_labels_path.write_text(labels_csv.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[ok] Updated app assets: {app_model_path} and {app_labels_path}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Train local food classifier for CalorieSnap")
    parser.add_argument("--food101-root", type=Path, default=Path("entrenarModeloNoAnyadirAGit"))
    parser.add_argument(
        "--ai4food-root",
        type=Path,
        default=Path("datasets/AI4Food-NutritionDB-generated/images_flat"),
    )
    parser.add_argument(
        "--ai4food-protocol-root",
        type=Path,
        default=Path("datasets/AI4Food-NutritionDB/experimental_protocol"),
    )
    parser.add_argument(
        "--ai4food-level",
        type=str,
        default="product",
        choices=["category", "subcategory", "product"],
    )
    parser.add_argument(
        "--ai4food-label-map-json",
        type=Path,
        default=Path("datasets/AI4Food-NutritionDB/product_label_map.json"),
    )
    parser.add_argument(
        "--nutrition5k-root",
        type=Path,
        default=Path("datasets/nutrition5k_dataset"),
    )
    parser.add_argument("--output-dir", type=Path, default=Path("training-artifacts/food-model-v3"))
    parser.add_argument("--min-class-samples", type=int, default=200)
    parser.add_argument("--max-per-class", type=int, default=2500)
    parser.add_argument("--train-ratio", type=float, default=0.7)
    parser.add_argument("--val-ratio", type=float, default=0.15)
    parser.add_argument(
        "--dedupe",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Remove exact duplicate images across merged datasets.",
    )
    parser.add_argument("--dedupe-hash-bytes", type=int, default=65536)
    parser.add_argument("--min-file-size-bytes", type=int, default=4096)
    parser.add_argument("--random-seed", type=int, default=42)

    parser.add_argument("--train", action="store_true")
    parser.add_argument("--image-size", type=int, default=192)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--epochs-head", type=int, default=8)
    parser.add_argument("--epochs-finetune", type=int, default=12)
    parser.add_argument("--learning-rate-head", type=float, default=1e-3)
    parser.add_argument("--learning-rate-finetune", type=float, default=1e-4)
    parser.add_argument("--focal-gamma", type=float, default=1.0)
    parser.add_argument("--focal-label-smoothing", type=float, default=0.02)
    parser.add_argument(
        "--balance-classes",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Apply inverse-frequency class weighting on training set.",
    )
    parser.add_argument("--class-weight-max", type=float, default=5.0)
    parser.add_argument("--mixup-alpha", type=float, default=0.2)
    parser.add_argument("--cutmix-alpha", type=float, default=0.8)
    parser.add_argument("--cutmix-prob", type=float, default=0.35)
    parser.add_argument("--backbone", type=str, default="efficientnetv2b0", choices=sorted(BACKBONES))
    parser.add_argument("--dropout", type=float, default=0.3)
    parser.add_argument("--unfreeze-layers", type=int, default=50)
    parser.add_argument(
        "--enable-mixed-precision",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Enable mixed precision only when TensorFlow can see a GPU.",
    )
    parser.add_argument(
        "--cache-train",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Cache train dataset to disk in output dir.",
    )
    parser.add_argument("--quantize-int8", action="store_true")
    parser.add_argument("--representative-size", type=int, default=400)
    parser.add_argument(
        "--skip-tflite-export",
        action="store_true",
        help="Train/evaluate and write reports/weights, but skip TFLite conversion.",
    )
    parser.add_argument(
        "--deploy-assets",
        action="store_true",
        help="Copy exported model/labels to assets/models/ for app inference.",
    )

    parser.add_argument(
        "--baseline-report-path",
        type=Path,
        default=Path("training-artifacts/food-model-real-v2/training_report.json"),
    )
    parser.add_argument(
        "--baseline-manifest-path",
        type=Path,
        default=Path("training-artifacts/food-model-real-v2/manifest.jsonl"),
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    random.seed(args.random_seed)
    samples: list[Sample] = []

    if args.food101_root is not None and args.food101_root.exists():
        food101_samples = _scan_food101(args.food101_root)
        samples.extend(food101_samples)
    else:
        print(f"[warn] Food-101 root not found: {args.food101_root}")
        food101_samples = []

    if args.ai4food_root is not None:
        if args.ai4food_root.exists():
            label_map = _load_label_map(args.ai4food_label_map_json)
            samples.extend(
                _scan_ai4food(
                    dataset_root=args.ai4food_root,
                    protocol_root=args.ai4food_protocol_root,
                    level=args.ai4food_level,
                    label_map=label_map,
                ),
            )
        else:
            print(f"[warn] AI4Food root not found: {args.ai4food_root}")

    if args.nutrition5k_root is not None:
        if args.nutrition5k_root.exists():
            samples.extend(_scan_nutrition5k(args.nutrition5k_root))
        else:
            print(f"[warn] Nutrition5k root not found: {args.nutrition5k_root}")

    if not samples:
        print("[error] No samples found. Check dataset paths.")
        return 1

    # Target taxonomy = curated food101-derived dish classes after canonical merge.
    target_classes = {sample.label for sample in food101_samples}
    if not target_classes:
        target_classes = {sample.label for sample in samples if sample.source.startswith("ai4food")}

    curated, dropped_initial, drop_reason_counts = _filter_and_curate_samples(
        samples,
        target_classes=target_classes,
        min_file_size_bytes=max(1024, int(args.min_file_size_bytes)),
    )
    if not curated:
        print("[error] No samples remain after initial curation.")
        return 1

    dedupe_stats = {
        "dedupe_candidates": 0,
        "dedupe_removed": 0,
        "dedupe_conflicting_label_removed": 0,
        "dedupe_io_errors": 0,
    }
    dedupe_drops: list[CurationLogRow] = []

    if args.dedupe:
        before = len(curated)
        curated, dedupe_stats, dedupe_drops = _deduplicate_samples(
            samples=curated,
            hash_bytes=max(1024, int(args.dedupe_hash_bytes)),
        )
        print(
            "[info] Dedupe:",
            f"{before} -> {len(curated)} samples,",
            f"removed={dedupe_stats['dedupe_removed']},",
            f"conflicting_labels={dedupe_stats['dedupe_conflicting_label_removed']},",
            f"io_errors={dedupe_stats['dedupe_io_errors']}",
        )

    curated = _cap_samples_per_class(
        curated,
        max_per_class=args.max_per_class,
        random_seed=args.random_seed,
    )

    # Build robust stratified split by class/source.
    curated = _rebalance_splits(
        curated,
        random_seed=args.random_seed,
        train_ratio=float(args.train_ratio),
        val_ratio=float(args.val_ratio),
    )

    curated, _valid_classes = _filter_classes(curated, min_count=max(1, args.min_class_samples))
    if not curated:
        print("[error] No samples remain after min-class filtering.")
        return 1

    # Re-run split balancing after dropping low support classes.
    curated = _rebalance_splits(
        curated,
        random_seed=args.random_seed,
        train_ratio=float(args.train_ratio),
        val_ratio=float(args.val_ratio),
    )

    out_dir: Path = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest_path, classes = _write_manifest(curated, out_dir)
    _write_summary(
        curated,
        classes,
        out_dir,
        dedupe_stats=dedupe_stats,
        drop_reason_counts=drop_reason_counts,
    )
    _write_curation_log(out_dir, [*dropped_initial, *dedupe_drops])

    taxonomy = _build_taxonomy_summary(curated, classes)
    (out_dir / "taxonomy.json").write_text(
        json.dumps(taxonomy, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    _write_audit_report(
        out_dir,
        baseline_report_path=args.baseline_report_path,
        baseline_manifest_path=args.baseline_manifest_path,
    )

    print(f"[ok] Wrote manifest: {manifest_path}")
    print(f"[ok] Classes: {len(classes)} | Samples: {len(curated)}")

    if not args.train:
        print("[info] Manifest created. Re-run with --train to train/export model.")
        return 0

    try:
        _train_and_export(
            samples=_read_manifest(manifest_path),
            classes=classes,
            out_dir=out_dir,
            image_size=args.image_size,
            batch_size=args.batch_size,
            epochs_head=args.epochs_head,
            epochs_finetune=args.epochs_finetune,
            learning_rate_head=args.learning_rate_head,
            learning_rate_finetune=args.learning_rate_finetune,
            focal_gamma=max(0.0, args.focal_gamma),
            focal_label_smoothing=max(0.0, min(0.2, args.focal_label_smoothing)),
            balance_classes=args.balance_classes,
            class_weight_max=max(1.0, args.class_weight_max),
            mixup_alpha=max(0.0, args.mixup_alpha),
            cutmix_alpha=max(0.0, args.cutmix_alpha),
            cutmix_prob=max(0.0, min(1.0, args.cutmix_prob)),
            quantize_int8=args.quantize_int8,
            representative_size=args.representative_size,
            deploy_assets=args.deploy_assets,
            backbone=args.backbone,
            dropout=max(0.0, min(0.8, args.dropout)),
            unfreeze_layers=max(0, args.unfreeze_layers),
            enable_mixed_precision=args.enable_mixed_precision,
            cache_train=args.cache_train,
            skip_tflite_export=args.skip_tflite_export,
        )
    except ModuleNotFoundError as exc:
        print(f"[error] Missing dependency: {exc}. Install TensorFlow first.")
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"[error] Training failed: {exc}")
        traceback.print_exc()
        return 3

    return 0


if __name__ == "__main__":
    sys.exit(main())
