import 'dart:math' as math;

/// Postprocessing for a single-label dish classifier. Classes represent
/// alternative dishes, never separate ingredients to add to a meal.
class ClassifierPostprocessing {
  static List<double> probabilities(
    List<double> scores, {
    bool logits = false,
  }) {
    if (scores.isEmpty) return const <double>[];
    // Invalid inference output must not turn into a plausible food.
    if (scores.any((score) => !score.isFinite)) {
      return List<double>.filled(scores.length, 0);
    }
    final sum = scores.fold<double>(0, (a, b) => a + b);
    // The shipped model has a softmax head. Quantized output rounding can
    // change its sum considerably; it must never receive a second softmax.
    if (!logits) {
      if (sum <= 0 || !scores.every((score) => score >= 0 && score <= 1)) {
        return List<double>.filled(scores.length, 0);
      }
      return scores.map((score) => score / sum).toList();
    }
    final maximum = scores.reduce(math.max);
    final exponentials =
        scores.map((score) => math.exp(score - maximum)).toList();
    final denominator = exponentials.fold<double>(0, (a, b) => a + b);
    return exponentials.map((score) => score / denominator).toList();
  }

  static int? winningClass(
    List<double> probabilities, {
    double minimum = 0.03,
  }) {
    if (probabilities.isEmpty || probabilities.any((p) => !p.isFinite)) {
      return null;
    }
    var winner = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[winner]) winner = i;
    }
    return probabilities[winner] >= minimum ? winner : null;
  }
}
