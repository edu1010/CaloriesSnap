import 'dart:convert';

import '../../nutrition/food_search.dart';

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

  /// Longest description passed on; more only costs prompt time.
  static const int maxDescriptionLength = 300;

  /// [hints] are the fast classifier's guesses. They are offered as weak
  /// evidence only; the classifier knows 116 dishes and is wrong on the rest.
  ///
  /// [description] is what the user wrote about the dish. Unlike the hints it
  /// is strong evidence: the person was there and knows what they ate and how
  /// it was cooked, which a photo often cannot show (oil, frying, fillings).
  static String user({
    required String languageCode,
    List<String> hints = const <String>[],
    String? description,
    List<FoodSuggestion> references = const <FoodSuggestion>[],
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
    final said = cleanDescription(description);
    if (said != null) {
      buffer
        ..writeln()
        ..writeln('The person who ate this meal says: "$said".')
        ..writeln(
          'Trust them about which foods these are and how they were cooked, '
          'and list every food they say they ate even if it is hard to see. '
          'Leave out foods they explicitly exclude. Use '
          'the photo for the amounts, unless they give a weight.',
        );
    }
    if (references.isNotEmpty) {
      buffer
        ..writeln('Local nutrition catalog matches for the description:')
        ..writeln(
          jsonEncode([
            for (final reference in references)
              {
                'name': reference.ingredient.variantName(
                  reference.variant,
                  languageCode,
                ),
                'kcal100': reference.variant.kcalPer100g,
                if (reference.ingredient.dish?.brand != null)
                  'wholeProduct': true,
                if (reference.ingredient.dish?.category == 'meal_powder')
                  'dryPowder': true,
                if (reference.ingredient.dish?.unitMillilitres != null)
                  'bottleMl': reference.ingredient.dish!.unitMillilitres,
                if (reference.grams != null)
                  (reference.gramsEstimated
                          ? 'estimatedGrams'
                          : 'enteredGrams'):
                      reference.grams
                else if (reference.quantity == null &&
                    reference.ingredient.dish?.unitGrams != null)
                  'unitGrams': reference.ingredient.dish!.unitGrams,
              },
          ]),
        )
        ..writeln(
          'Use these names and kcal100 for matching foods. Keep enteredGrams '
          'as written and use estimatedGrams as the catalog portion. unitGrams gives '
          'the standard weight of one unit. For dryPowder, use the dry serving '
          'weight, excluding mixing water. For bottleMl, use the drink volume '
          'in the grams field. A wholeProduct is '
          'one item with its standard ingredients included. Only list extra items '
          'actually eaten, such as a side.',
        );
    }
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

  /// One line, no quotes that could close the prompt's quotation, and at
  /// most [maxDescriptionLength] characters. Null when nothing is left.
  static String? cleanDescription(String? description) {
    if (description == null) return null;
    var text =
        description
            .replaceAll(RegExp(r'["“”]'), "'")
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    if (text.length > maxDescriptionLength) {
      text = text.substring(0, maxDescriptionLength).trimRight();
    }
    return text.isEmpty ? null : text;
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
