# CalorieSnap

CalorieSnap is an offline Flutter app for Android and Windows desktop to register meals from photos and estimate calories as a range (approximate, not exact).

## What v1 includes

- Home dashboard with:
  - "Register meal"
  - "Calendar"
  - Today total approximate calories
  - Number of meals today
- Register flow:
  - Android: take photo (camera) or pick from gallery
  - Windows: pick image from disk
  - Barcode alternative:
    - Android/iOS/macOS: scan with camera
    - Windows: type barcode (or USB/Bluetooth scanner as keyboard input)
    - Lookup order: local AESAN dataset first, then Open Food Facts fallback
  - Local on-device food detection result (TensorFlow Lite)
  - Editable food confirmation (name, grams, kcal/100g, portion size)
  - Meal summary with estimated range (0.8x to 1.2x)
  - Save meal locally
- Calendar:
  - Monthly view
  - Per-day meals count + kcal marker
  - Tap day for daily details
- Daily details:
  - Total kcal and meal count
  - Meal list with meal type/time/kcal/thumbnail
  - Open meal detail
  - Delete meal
- Meal detail:
  - Full meal data
  - Edit (re-open food confirmation + summary save)
  - Delete

## Tech stack

- Flutter + Dart
- SQLite local persistence (`sqflite`, `sqflite_common_ffi` for Windows)
- Local JSON nutrition databases:
  - Generic foods: `lib/data/local/nutrition_database.json`
  - Classifier dishes: `lib/data/local/food101_nutrition.json`
  - Everyday Spanish foods, sandwiches and ready meals:
    `lib/data/local/common_foods_es.json` (built by `tooling/build_common_foods_es.py`)
  - Packaged products (AESAN import): `lib/data/local/nutrition_products_es.json`
- `image_picker` for Android camera/gallery
- `file_picker` for Windows file selection
- `mobile_scanner` for camera barcode scanning
- `table_calendar` for monthly calendar UI

## Project structure

This project follows the requested modular architecture under `lib/`:

- `core/` theme, constants, utils
- `models/` domain models
- `data/repositories/` local data access
- `services/` detection, image storage, calorie calculator
- `features/` UI flows by feature

## Run the app

If your repo does not yet include `android/` and `windows/` folders, generate platform scaffolding once:

```bash
flutter create . --platforms=android,windows
```

Then install dependencies:

```bash
flutter pub get
```

### Run on Android

```bash
flutter run -d android
```

### Run on Windows

```bash
flutter run -d windows
```

## Build

### Build APK

```bash
flutter build apk
```

### Build Windows release

```bash
flutter build windows
```

## Current limitations

- Without the optional vision model, photo detection is limited to the 116 classifier dishes.
- With it, grams are a visual estimate by a small model and analysis takes much longer than the classifier.
- Barcode flow depends on EAN availability and nutrition quality in AESAN/Open Food Facts.
- Calorie output is intentionally approximate and should not be treated as medical or clinical measurement.
- Windows webcam capture is not enabled in this v1 (image selection from disk is supported).
- Platform-native setup files are not included in this repository snapshot unless you run `flutter create`.

## Nutrition data sources

- AESAN (official Spanish dataset, 2022): imported from Excel into local JSON for offline lookup by barcode.
- Open Food Facts: used as online fallback only when barcode is not found locally.
  - API usage requires a custom `User-Agent`.
  - Data license is ODbL with attribution/share-alike requirements.

## Data licenses and attribution

- AESAN dataset (Base de datos de alimentos y bebidas comercializados en España 2022):
  - Source: [AESAN Alimentos y Bebidas](https://www.aesan.gob.es/AECOSAN/web/seguridad_alimentaria/subseccion/alimentosBebidas.htm)
  - Important note: AESAN indicates these data were collected by third parties and may change over time; product names/brands are informational and do not imply endorsement.
- Open Food Facts:
  - Terms and reuse: [Open Food Facts terms of use](https://world.openfoodfacts.org/terms-of-use)
  - API conditions summary: [Open Food Facts API reuse conditions](https://support.openfoodfacts.org/help/es-es/12-api-y-reutilizacion-de-datos/94-existen-condiciones-para-utilizar-la-api)
  - Key obligations when reusing data:
    - Attribution.
    - Share-alike obligations from ODbL when distributing a derived database.
    - Use a custom `User-Agent` and respect API rate limits.
- Nutrition5k:
  - Repository: [google-research-datasets/Nutrition5k](https://github.com/google-research-datasets/Nutrition5k)
  - License: Creative Commons 4.0 (as specified by the dataset authors).
- AI4Food-NutritionDB:
  - Repository: [BiDAlab/AI4Food-NutritionDB](https://github.com/BiDAlab/AI4Food-NutritionDB)
  - Follow the dataset authors' download/reuse instructions and citation requirements.

If you redistribute builds or exported datasets, review those terms before publication.

### Rebuild AESAN local JSON

If you download a newer AESAN Excel, rebuild the local product JSON with:

```bash
python tooling/import_aesan_products.py --input C:/path/BasedatosWeb.xlsx --output lib/data/local/nutrition_products_es.json
```

## Local AI food detection (TensorFlow Lite)

1. Runtime service:
   - `lib/services/food_detection/local_ai_food_detection_service.dart`
2. Interface contract kept unchanged:
   - `FoodDetectionService.detectFoods(String imagePath)`
3. App wiring:
   - `lib/main.dart` now uses `LocalAiFoodDetectionService`
4. Model assets:
   - `assets/models/food_classifier.tflite`
   - `assets/models/food_classifier_labels.csv`
   - Windows runtime DLL in `blobs/libtensorflowlite_c-win.dll` (see `blobs/README.md`)
5. Output shape in app flow:
   - `DetectedFood(name, confidence, suggestedGrams, kcalPer100g)`
6. Platform requirements:
   - Android `minSdk` is set to `26` for TensorFlow Lite runtime compatibility

## On-device vision model (optional, Qwen3.5)

The classifiers know 116 dishes and return one food per photo. For everything
else (a sandwich, a ready meal, a combo plate) the app can run a small
vision-language model **on the device**:

1. The TFLite classifiers run first (about 0.2 s) and their guesses become hints.
2. Qwen3.5 (GGUF, llama.cpp through `llamadart`) describes the plate as JSON:
   dish name, components, grams and a proposed kcal/100 g.
3. `NutritionGrounding` looks every component up in the local nutrition tables.
   A table hit replaces the model's energy value; a miss keeps the model's
   value and the confirmation screen flags it as an estimate.
4. The user reviews and edits everything, as before.

If no model is downloaded, or it fails, times out or answers garbage, the
classifier result is used. Code: `lib/services/food_detection/vlm/` and
`cascade_meal_analysis_service.dart`.

The model is not bundled. It is downloaded once from **On-device AI** (the
sparkle icon on the home screen), resumable and SHA-256 verified:

| Tier | Files | Download | Suggested RAM |
| --- | --- | ---: | --- |
| Light | `Qwen3.5-0.8B-Q4_K_M.gguf` + `mmproj-F16.gguf` | 0.7 GB | 4 GB+ |
| Precise | `Qwen3.5-2B-Q4_K_M.gguf` + `mmproj-F16.gguf` | 1.9 GB | 8 GB+ |

Models: [unsloth/Qwen3.5-0.8B-GGUF](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF)
and [unsloth/Qwen3.5-2B-GGUF](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF),
Apache-2.0, pinned by revision in `vlm_model_catalog.dart`.

Plan, status and measurements: `docs/PLAN_VLM_QWEN.md`.

## Offline and privacy

- No paid API required
- No login required
- No cloud storage required
- All data is local on device
- Photos are analysed on the device; the only downloads are the optional
  vision model (once) and Open Food Facts barcode lookups
