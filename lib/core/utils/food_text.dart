/// Text helpers shared by food search and description parsing.
///
/// Matching is accent- and case-insensitive so "brocoli", "Brócoli" and
/// "BROCOLI" are the same word.
library;

const Map<String, String> _accents = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ł': 'l',
  'ś': 's',
  'ę': 'e',
};

/// Lower-case, accent-free words of [value], digits kept.
List<String> foodWords(String value) {
  var text = value.toLowerCase().replaceAll(RegExp(r"['’]s\b"), 's');
  _accents.forEach((accented, plain) {
    text = text.replaceAll(accented, plain);
  });
  return text
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((word) => word.isNotEmpty)
      .toList();
}

/// [foodWords] joined by single spaces.
String normalizeFoodText(String value) => foodWords(value).join(' ');

/// Light singular form so "patatas" finds "patata" and "huevos" "huevo".
String singularFoodWord(String word) {
  if (word.length > 4 && word.endsWith('es') && !word.endsWith('ses')) {
    final stem = word.substring(0, word.length - 2);
    // "limones" -> "limon", but "tomates" -> "tomate" (handled below).
    if (RegExp(r'[nlrdz]$').hasMatch(stem)) return stem;
  }
  if (word.length > 3 && word.endsWith('s')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}
