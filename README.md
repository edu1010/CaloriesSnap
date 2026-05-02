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

- Photo detection quality is constrained by the local TensorFlow Lite model classes and confidence.
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

## Offline and privacy

- No paid API required
- No login required
- No cloud storage required
- All data is local on device
