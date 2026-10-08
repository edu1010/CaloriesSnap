import 'dart:convert';

/// One component of a meal as described by the vision-language model.
class AnalyzedItem {
  const AnalyzedItem({
    required this.name,
    this.nameEn,
    this.grams,
    this.kcalPer100g,
  });

  /// Name in the user's language.
  final String name;

  /// English name, only used to look the food up in the nutrition table.
  final String? nameEn;
  final double? grams;
  final double? kcalPer100g;
}

/// Parsed answer of the vision-language model for one photo.
class MealAnalysis {
  const MealAnalysis({
    required this.isFood,
    required this.items,
    this.dish,
  });

  static const int maxItems = 8;

  final bool isFood;
  final String? dish;
  final List<AnalyzedItem> items;

  /// Small models wrap, truncate and decorate their JSON. This accepts the
  /// first JSON object found in [raw] and returns null when nothing usable is
  /// left, so the caller can fall back to the classifier.
  static MealAnalysis? tryParse(String raw) {
    final decoded = _decodeFirstObject(_stripReasoning(raw));
    if (decoded == null) return null;

    final rawItems = decoded['items'];
    final items = <AnalyzedItem>[];
    final seen = <String>{};
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is! Map) continue;
        final name = _text(entry['name']) ?? _text(entry['en']);
        // Small models sometimes loop over the same item until the token
        // limit; a repeated name is never a second portion.
        if (name == null || !seen.add(name.toLowerCase())) continue;
        items.add(
          AnalyzedItem(
            name: name,
            nameEn: _text(entry['en']) ?? _text(entry['name_en']),
            grams: _number(entry['grams'] ?? entry['g']),
            kcalPer100g: _number(
              entry['kcal100'] ?? entry['kcal_per_100g'] ?? entry['kcal'],
            ),
          ),
        );
        if (items.length == maxItems) break;
      }
    }

    final food = decoded['food'] ?? decoded['is_food'];
    final isFood = food is bool ? food : items.isNotEmpty;
    return MealAnalysis(
      isFood: isFood && items.isNotEmpty,
      dish: _text(decoded['dish']),
      items: isFood ? items : const <AnalyzedItem>[],
    );
  }

  static String _stripReasoning(String raw) {
    var text = raw.replaceAll(
      RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false),
      '',
    );
    // An unterminated reasoning block means the answer never started.
    final open = text.toLowerCase().lastIndexOf('<think>');
    if (open >= 0) text = text.substring(0, open);
    return text;
  }

  static Map<String, dynamic>? _decodeFirstObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    final candidate = _balancedPrefix(text.substring(start));
    for (final attempt in <String>[candidate, _dropTrailingCommas(candidate)]) {
      try {
        final value = jsonDecode(attempt);
        if (value is Map<String, dynamic>) return value;
      } on FormatException {
        // Try the next repair.
      }
    }
    return null;
  }

  /// Returns [text] cut at the end of its first complete object. When the
  /// output was truncated by the token limit, the open string, arrays and
  /// objects are closed so the items generated so far are not lost.
  static String _balancedPrefix(String text) {
    final closers = <String>[];
    var inString = false;
    var escaped = false;
    // End of the last complete value inside an array/object, so a half-written
    // trailing element can be discarded.
    var lastSafe = -1;
    var safeDepth = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      switch (char) {
        case '"':
          inString = true;
        case '{':
          closers.add('}');
        case '[':
          closers.add(']');
        case '}' || ']':
          if (closers.isEmpty) return text.substring(0, i);
          closers.removeLast();
          if (closers.isEmpty) return text.substring(0, i + 1);
          lastSafe = i + 1;
          safeDepth = closers.length;
      }
    }
    if (lastSafe < 0) return text;
    return text.substring(0, lastSafe) +
        closers.sublist(0, safeDepth).reversed.join();
  }

  static String _dropTrailingCommas(String text) =>
      text.replaceAll(RegExp(r',\s*(?=[}\]])'), '');

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    // "..." and "?" are placeholders, not names.
    return RegExp(r'\p{L}', unicode: true).hasMatch(trimmed) ? trimmed : null;
  }

  static double? _number(Object? value) {
    if (value is num) return value.isFinite ? value.toDouble() : null;
    if (value is String) {
      // "150 g", "~250", "1,5".
      final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(value);
      if (match == null) return null;
      return double.tryParse(match.group(0)!.replaceAll(',', '.'));
    }
    return null;
  }
}
