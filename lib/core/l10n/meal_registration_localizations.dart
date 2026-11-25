import 'app_localizations.dart';

extension MealRegistrationLocalizations on AppLocalizations {
  bool get _spanish => locale.languageCode == 'es';

  String get registerFromText =>
      _spanish ? 'Registrar sin foto' : 'Log without a photo';

  String get saveWithoutWaiting =>
      _spanish ? 'Guardar sin esperar' : 'Save without waiting';

  String get advancedSuggestions =>
      _spanish ? 'Sugerencias de IA' : 'AI suggestions';

  String get nothingToAdd =>
      _spanish
          ? 'La IA no encontró otros alimentos.'
          : 'AI found no other foods.';

  String get currentWeight => _spanish ? 'Gramos indicados' : 'Entered grams';

  String get weighedRawOrCooked =>
      _spanish
          ? '¿Lo pesaste en crudo o cocido?'
          : 'Did you weigh it raw or cooked?';

  String get rawWeight => _spanish ? 'En crudo' : 'Raw';
  String get cookedWeight => _spanish ? 'Cocido' : 'Cooked';

  String enterQuantityWeight(String quantity) =>
      _spanish
          ? 'Indica el peso de «$quantity»'
          : 'Enter the weight for “$quantity”';

  String convertedQuantity(String quantity) =>
      _spanish ? 'Conversión de «$quantity»' : 'Converted from “$quantity”';

  String suggestedPortion(String food, String grams) =>
      _spanish ? '$food · aprox. $grams g' : '$food · about $grams g';

  String adjustToSuggestedPortion(String food, String grams) =>
      _spanish ? '$food · ajustar a $grams g' : '$food · adjust to $grams g';

  String get energyEstimatedByAi =>
      _spanish ? 'Estimadas por IA' : 'Estimated by AI';

  String get reviewAiBreakdown =>
      _spanish ? 'Usar desglose de IA' : 'Use AI breakdown';

  String get reviewAiBreakdownHelp =>
      _spanish
          ? 'Puedes sustituir la sugerencia de la foto por sus ingredientes.'
          : 'You can replace the photo suggestion with its ingredients.';
}
