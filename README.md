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
- Local JSON nutrition database (`lib/data/local/nutrition_database.json`)
- `image_picker` for Android camera/gallery
- `file_picker` for Windows file selection
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

- Food detection uses a local TensorFlow Lite model and maps dish labels to a small nutrition set (`Rice cooked`, `Chicken breast`, `Pasta cooked`, `Bread`, `Egg`, `Salad`, `Olive oil`).
- Calorie output is intentionally approximate and should not be treated as medical or clinical measurement.
- Windows webcam capture is not enabled in this v1 (image selection from disk is supported).
- Platform-native setup files are not included in this repository snapshot unless you run `flutter create`.

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
