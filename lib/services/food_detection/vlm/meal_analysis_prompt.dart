/// Prompt and output contract for the on-device vision-language model.
///
/// Keys are short on purpose: every output token costs time on a phone. The
/// wording was tuned against `test/vlm_native_benchmark_test.dart`; small
/// models copy placeholders such as "..." or 0 literally, so the example is a
/// concrete meal.
class MealAnalysisPrompt {
  const MealAnalysisPrompt._();

  static const int maxOutputTokens = 320;

  static const String system =
      'You are a nutrition assistant. You look at one photo of a meal and '
      'answer with JSON only.';

  /// [hints] are the fast classifier's guesses. They are offered as weak
  /// evidence only; the classifier knows 116 dishes and is wrong on the rest.
  static String user({
    required String languageCode,
    List<String> hints = const <String>[],
  }) {
    final spanish = languageCode == 'es';
    final language = spanish ? 'Spanish' : 'English';
    final example =
        spanish
            ? '{"food":true,"dish":"Filete con patatas y ensalada","items":['
                '{"name":"filete de ternera","en":"beef steak","grams":170,"kcal100":220},'
                '{"name":"patatas fritas","en":"french fries","grams":110,"kcal100":310},'
                '{"name":"ensalada","en":"salad","grams":60,"kcal100":25}]}'
            : '{"food":true,"dish":"Steak with fries and salad","items":['
                '{"name":"beef steak","en":"beef steak","grams":170,"kcal100":220},'
                '{"name":"french fries","en":"french fries","grams":110,"kcal100":310},'
                '{"name":"salad","en":"salad","grams":60,"kcal100":25}]}';
    final buffer =
        StringBuffer()
          ..writeln(
            'Look at the photo. What food is on it and how much does it weigh?',
          )
          ..writeln()
          ..writeln(
            '- "food": true when the photo shows food or drink, false '
            'otherwise (then "items" is empty).',
          )
          ..writeln('- "dish": name of the whole meal, in $language.')
          ..writeln(
            '- "items": each different food you can see, listed once, at most '
            '6. A mixed dish that cannot be separated (paella, lasagna, stew, '
            'pizza) is a single item. For a sandwich list the bread and each '
            'filling.',
          )
          ..writeln('- "name": the food, in $language.')
          ..writeln('- "en": the same food in English.')
          ..writeln(
            '- "grams": weight of the portion in the photo. Judge it from the '
            'plate and cutlery; a full main dish weighs 250 to 450 g.',
          )
          ..writeln('- "kcal100": kcal per 100 g of that food.')
          ..writeln()
          ..writeln('Example for a different photo: $example');
    if (hints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'A weak classifier guessed: ${hints.join(', ')}. It is often '
          'wrong; ignore it unless it matches what you see.',
        );
    }
    buffer
      ..writeln()
      ..write('Now answer for this photo.');
    return buffer.toString();
  }

  /// OpenAI-style `response_format`; llama.cpp compiles it to a grammar so
  /// the model cannot emit anything but this shape.
  static const Map<String, dynamic> responseFormat = <String, dynamic>{
    'type': 'json_schema',
    'json_schema': <String, dynamic>{
      'name': 'meal',
      'schema': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'food': <String, dynamic>{'type': 'boolean'},
          'dish': <String, dynamic>{'type': 'string'},
          'items': <String, dynamic>{
            'type': 'array',
            'maxItems': 6,
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'name': <String, dynamic>{'type': 'string'},
                'en': <String, dynamic>{'type': 'string'},
                'grams': <String, dynamic>{
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 2000,
                },
                'kcal100': <String, dynamic>{
                  'type': 'integer',
                  'minimum': 0,
                  'maximum': 900,
                },
              },
              'required': <String>['name', 'en', 'grams', 'kcal100'],
            },
          },
        },
        'required': <String>['food', 'dish', 'items'],
      },
    },
  };
}
