import 'package:calorie_snap/services/food_detection/classifier_postprocessing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:calorie_snap/services/food_detection/classifier_image_preprocessing.dart';

void main() {
  test('16-bit image channels are converted to the expected RGB8 range', () {
    final photograph = img.Image(
      width: 2,
      height: 2,
      format: img.Format.uint16,
    );
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        photograph.setPixelRgb(x, y, 65535, 32768, 0);
      }
    }
    final input = prepareClassifierImage(photograph, 2, 2);
    expect(input.getPixel(0, 0).r, 255);
    expect(input.getPixel(0, 0).g, closeTo(128, 1));
    expect(input.getPixel(0, 0).b, 0);
  });
  test('quantized softmax sums outside 0.8 to 1.2 stay probabilities', () {
    final probabilities = ClassifierPostprocessing.probabilities([0.6, 0.1]);
    expect(probabilities.first, closeTo(6 / 7, 1e-10));
  });
  test('training resize retains food at both photograph edges', () {
    final photograph = img.Image(width: 12, height: 4);
    for (var y = 0; y < photograph.height; y++) {
      for (var x = 0; x < photograph.width; x++) {
        photograph.setPixelRgb(x, y, x < 4 ? 255 : 0, 0, x >= 8 ? 255 : 0);
      }
    }
    final input = prepareClassifierImage(photograph, 6, 6);
    expect(input.width, 6);
    expect(input.height, 6);
    expect(input.getPixel(0, 3).r, greaterThan(200));
    expect(input.getPixel(5, 3).b, greaterThan(200));
  });
  test(
    'normalizes quantized probabilities without applying a second softmax',
    () {
      final probabilities = ClassifierPostprocessing.probabilities([
        0.7,
        0.2,
        0.09,
      ]);
      expect(probabilities[0], closeTo(0.7 / 0.99, 1e-10));
      expect(probabilities.reduce((a, b) => a + b), closeTo(1, 1e-10));
    },
  );

  test('softmax is stable for very large logits', () {
    final probabilities = ClassifierPostprocessing.probabilities([
      10000,
      9999,
    ], logits: true);
    expect(probabilities[0], closeTo(0.7310585786, 1e-9));
  });

  test('invalid scores cannot hallucinate a confident dish', () {
    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        ClassifierPostprocessing.winningClass(
          ClassifierPostprocessing.probabilities([invalid, 0.8]),
        ),
        isNull,
      );
    }
  });

  test('diffuse predictions abstain and one dominant class wins', () {
    expect(
      ClassifierPostprocessing.winningClass(List.filled(120, 1 / 120)),
      isNull,
    );
    expect(ClassifierPostprocessing.winningClass([0.2, 0.6, 0.2]), 1);
    expect(ClassifierPostprocessing.winningClass([]), isNull);
  });
}
