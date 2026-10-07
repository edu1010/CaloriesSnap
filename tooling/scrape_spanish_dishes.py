#!/usr/bin/env python3
"""Scrape + clean training images for Spanish dishes that Food-101 lacks.

Downloads images per dish from DuckDuckGo image search (ddgs, no API key), then
runs a cleaning pass: validates with PIL, drops corrupt/tiny images, converts to
RGB JPEG, and de-duplicates by content hash. Output is a Food-101-style folder
tree (images/<Class>/*.jpg) ready for the training pipeline.

NOTE: icrawler's BingImageCrawler was tried first and is broken (Bing changed
its results markup), silently downloading images unrelated to the query.

Usage (close GPU apps not needed; this is CPU/network only):
  PYTHONPATH=tooling .venv-training-dml310/Scripts/python.exe \
    tooling/scrape_spanish_dishes.py --per-dish 400 --min-side 256

Re-running is safe: cleaning de-dupes, and --skip-existing avoids re-crawling
dishes that already have enough cleaned images.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import shutil
from pathlib import Path

from PIL import Image

# Canonical label (ASCII, Title Case) -> (display_es, [search queries])
DISHES: dict[str, tuple[str, list[str]]] = {
    "Tortilla De Patatas": ("Tortilla de patatas", [
        "tortilla de patatas española", "spanish potato omelette tortilla",
        "tortilla de patata plato", "tortilla española pincho",
        "tortilla de patatas receta casera", "tortilla de patatas con cebolla",
        "tortilla de patatas jugosa", "spanish tortilla slice",
        "pincho de tortilla bar",
    ]),
    "Croquetas": ("Croquetas", [
        "croquetas de jamón españolas", "spanish croquettes plate",
        "croquetas caseras", "croquetas de bacalao tapa",
        "croquetas de pollo racion", "croquetas cremosas receta",
        "croquetas de jamon ibérico restaurante", "croquetas fritas plato",
        "tapa de croquetas",
    ]),
    "Gazpacho": ("Gazpacho", [
        "gazpacho andaluz bowl", "gazpacho tomato cold soup",
        "gazpacho español vaso", "gazpacho cuenco",
        "gazpacho andaluz receta", "gazpacho casero verano",
        "gazpacho con guarnición", "gazpacho andaluz tradicional",
        "sopa fria gazpacho",
    ]),
    "Salmorejo": ("Salmorejo", [
        "salmorejo cordobés", "salmorejo con huevo y jamón",
        "salmorejo plato", "salmorejo bowl spanish",
        "salmorejo casero receta", "salmorejo de córdoba tradicional",
        "salmorejo crema fria", "salmorejo tapa",
    ]),
    "Patatas Bravas": ("Patatas bravas", [
        "patatas bravas salsa brava", "spanish patatas bravas tapa",
        "patatas bravas plato", "bravas con alioli",
        "patatas bravas caseras", "patatas bravas madrid bar",
        "patatas bravas racion", "patatas bravas restaurante",
    ]),
    "Pulpo A La Gallega": ("Pulpo a la gallega", [
        "pulpo a la gallega pimentón", "galician octopus pulpo plate",
        "pulpo a feira", "pulpo a la gallega tabla",
        "pulpo a la gallega con cachelos", "pulpo gallego racion",
        "pulpo a la gallega receta", "octopus galician style paprika",
    ]),
    "Jamon Serrano": ("Jamón serrano", [
        "plato de jamón serrano", "spanish cured ham jamón plate",
        "jamón ibérico loncheado", "tabla de jamón serrano",
        "jamon serrano lonchas finas", "racion de jamon iberico",
        "jamon serrano cortado a cuchillo", "plato jamon iberico bellota",
    ]),
    "Fabada Asturiana": ("Fabada asturiana", [
        "fabada asturiana plato", "asturian bean stew fabada",
        "fabada con compango", "fabada asturiana cuchara",
        "fabada asturiana casera", "fabada asturiana receta tradicional",
        "fabada asturiana cazuela", "fabes con chorizo y morcilla",
    ]),
    "Pimientos De Padron": ("Pimientos de padrón", [
        "pimientos de padrón fritos", "padron peppers tapa",
        "pimientos de padrón plato", "pementos de padrón",
        "pimientos de padron con sal gorda", "pimientos de padron racion",
        "pimientos del padron fritos aceite", "padron peppers fried",
    ]),
    "Gambas Al Ajillo": ("Gambas al ajillo", [
        "gambas al ajillo cazuela", "garlic shrimp gambas al ajillo",
        "gambas al ajillo español", "gambas al ajillo guindilla",
        "gambas al ajillo receta", "gambas al ajillo cazuela de barro",
        "gambas al ajillo tapa", "sizzling garlic prawns spanish",
    ]),
    "Empanada Gallega": ("Empanada gallega", [
        "empanada gallega atún", "galician empanada slice",
        "empanada gallega plato", "empanada gallega porción",
        "empanada gallega casera", "empanada gallega de bonito",
        "empanada gallega entera", "empanada gallega receta horno",
    ]),
    "Ensaladilla Rusa": ("Ensaladilla rusa", [
        "ensaladilla rusa española", "spanish russian salad ensaladilla",
        "ensaladilla rusa tapa", "ensaladilla rusa plato",
        "ensaladilla rusa casera", "ensaladilla rusa con mayonesa",
        "ensaladilla rusa racion bar", "ensaladilla rusa receta",
    ]),
    "Tarta De Santiago": ("Tarta de Santiago", [
        "tarta de santiago almendra", "santiago almond cake cross",
        "tarta de santiago porción", "tarta de santiago cruz",
        "tarta de santiago casera", "tarta de santiago receta gallega",
        "tarta de santiago azucar glas", "tarta de almendra gallega",
    ]),
    "Bocadillo De Calamares": ("Bocadillo de calamares", [
        "bocadillo de calamares madrid", "calamari sandwich bocadillo",
        "bocata de calamares", "bocadillo calamares plato",
        "bocadillo de calamares plaza mayor", "bocadillo de calamares con pan",
        "bocadillo de calamares fritos", "bocata calamares bar",
    ]),
    "Albondigas": ("Albóndigas", [
        "albóndigas en salsa españolas", "spanish meatballs in sauce albondigas",
        "albóndigas caseras plato", "albóndigas con tomate",
        "albondigas en salsa receta", "albondigas de ternera guisadas",
        "albondigas con patatas", "albondigas cazuela española",
    ]),
}


_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)


def _search_image_urls(queries: list[str], per_dish: int) -> list[str]:
    """Collect candidate image URLs from DuckDuckGo, deduped, round-robin fair.

    Each query runs in both the Spanish and the global region: DDG caps
    results per query (~100-200), so region variation is how we get volume.
    """
    import time

    from ddgs import DDGS

    per_query = max(1, per_dish // len(queries) + 25)
    urls: list[str] = []
    seen: set[str] = set()
    for q in queries:
        for region in ("es-es", "wt-wt"):
            try:
                # safesearch="on" (strict): training data must stay free of
                # NSFW results that "moderate" occasionally lets through.
                results = DDGS().images(
                    q,
                    region=region,
                    safesearch="on",
                    max_results=per_query,
                )
            except Exception as e:  # noqa: BLE001
                print(f"    [warn] query {q!r} ({region}) failed: {e}")
                continue
            for r in results or []:
                url = (r or {}).get("image", "")
                if url and url not in seen:
                    seen.add(url)
                    urls.append(url)
            time.sleep(1.0)  # be gentle with the search endpoint
    return urls


def _download_one(url: str, dest: Path) -> bool:
    import requests

    try:
        resp = requests.get(url, timeout=10, headers={"User-Agent": _UA})
        resp.raise_for_status()
        data = resp.content
        if len(data) < 4096:
            return False
        dest.write_bytes(data)
        return True
    except Exception:  # noqa: BLE001
        return False


def crawl_dish(label: str, queries: list[str], raw_dir: Path, per_dish: int) -> None:
    from concurrent.futures import ThreadPoolExecutor

    raw_dir.mkdir(parents=True, exist_ok=True)
    urls = _search_image_urls(queries, per_dish)
    print(f"    {len(urls)} candidate URLs")
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [
            pool.submit(_download_one, url, raw_dir / f"{i:05d}.img")
            for i, url in enumerate(urls)
        ]
        ok = sum(1 for f in futures if f.result())
    print(f"    downloaded {ok}/{len(urls)}")


def clean_dish(raw_dir: Path, out_dir: Path, min_side: int, max_keep: int) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    seen: set[str] = set()
    kept = 0
    for src in sorted(raw_dir.rglob("*")):
        if not src.is_file():
            continue
        try:
            with Image.open(src) as im:
                im = im.convert("RGB")
                if min(im.size) < min_side:
                    continue
                buf = io.BytesIO()
                im.save(buf, format="JPEG", quality=90)
                data = buf.getvalue()
        except Exception:
            continue
        h = hashlib.md5(data).hexdigest()
        if h in seen:
            continue
        seen.add(h)
        (out_dir / f"{h}.jpg").write_bytes(data)
        kept += 1
        if kept >= max_keep:
            break
    return kept


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path("datasets/spanish_dishes"))
    ap.add_argument("--per-dish", type=int, default=400)
    ap.add_argument("--min-side", type=int, default=256)
    ap.add_argument("--max-keep", type=int, default=600)
    ap.add_argument("--skip-existing", type=int, default=200,
                    help="Skip crawling a dish that already has >= this many cleaned images.")
    ap.add_argument("--only", type=str, default="", help="Comma-separated subset of labels.")
    ap.add_argument("--keep-raw", action="store_true")
    args = ap.parse_args()

    raw_root = args.root / "raw"
    img_root = args.root / "images"
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    summary = []
    for label, (es, queries) in DISHES.items():
        if only and label not in only:
            continue
        out_dir = img_root / label
        existing = len(list(out_dir.glob("*.jpg"))) if out_dir.exists() else 0
        if existing >= args.skip_existing:
            print(f"[skip] {label}: already {existing} images")
            summary.append((label, existing))
            continue
        print(f"[crawl] {label} ({es}) ...")
        raw_dir = raw_root / label
        crawl_dish(label, queries, raw_dir, args.per_dish)
        kept = clean_dish(raw_dir, out_dir, args.min_side, args.max_keep)
        if not args.keep_raw:
            shutil.rmtree(raw_dir, ignore_errors=True)
        print(f"[done]  {label}: kept {kept} cleaned images")
        summary.append((label, kept))

    print("\n==== SUMMARY ====")
    total = 0
    for label, n in summary:
        total += n
        flag = "" if n >= 150 else "  <-- LOW"
        print(f"  {n:4d}  {label}{flag}")
    print(f"  total: {total} across {len(summary)} dishes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
