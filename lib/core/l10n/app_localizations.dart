import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('es')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  bool get _isSpanish => locale.languageCode.toLowerCase().startsWith('es');

  String get appTitle => _isSpanish ? 'CalorieSnap' : 'CalorieSnap';
  String get today => _isSpanish ? 'Hoy' : 'Today';
  String get approximateCalories =>
      _isSpanish ? 'Calorías aproximadas' : 'Approximate calories';
  String get estimatedRange =>
      _isSpanish ? 'Rango estimado' : 'Estimated range';
  String get mealsRegistered =>
      _isSpanish ? 'Comidas registradas' : 'Meals registered';
  String get registerMeal => _isSpanish ? 'Registrar comida' : 'Register meal';
  String get calendar => _isSpanish ? 'Calendario' : 'Calendar';
  String get foods => _isSpanish ? 'Alimentos' : 'Foods';
  String get notes => _isSpanish ? 'Notas' : 'Notes';
  String get noNotes => _isSpanish ? 'Sin notas' : 'No notes';
  String get edit => _isSpanish ? 'Editar' : 'Edit';
  String get delete => _isSpanish ? 'Eliminar' : 'Delete';
  String get cancel => _isSpanish ? 'Cancelar' : 'Cancel';
  String get continueText => _isSpanish ? 'Continuar' : 'Continue';
  String get save => _isSpanish ? 'Guardar' : 'Save';
  String get mealType => _isSpanish ? 'Tipo de comida' : 'Meal type';
  String get optionalMealNotes =>
      _isSpanish ? 'Notas opcionales de la comida' : 'Optional meal notes';
  String get addFood => _isSpanish ? 'Añadir alimento' : 'Add food';
  String get customFood =>
      _isSpanish ? 'Alimento personalizado' : 'Custom food';
  String get knownFood => _isSpanish ? 'Alimento conocido' : 'Known food';
  String get name => _isSpanish ? 'Nombre' : 'Name';
  String get estimatedGrams =>
      _isSpanish ? 'Gramos estimados' : 'Estimated grams';
  String get kcalPer100g => _isSpanish ? 'kcal por 100g' : 'kcal per 100g';
  String get portionSize => _isSpanish ? 'Tamaño de ración' : 'Portion size';
  String get remove => _isSpanish ? 'Quitar' : 'Remove';
  String get searching => _isSpanish ? 'Buscando...' : 'Searching...';
  String get useBarcode => _isSpanish ? 'Usar código de barras' : 'Use barcode';
  String get alternativeBarcode =>
      _isSpanish ? 'Alternativa: código de barras' : 'Alternative: barcode';
  String get scanWithCamera =>
      _isSpanish ? 'Escanear con cámara' : 'Scan with camera';
  String get scanOrEnterCode =>
      _isSpanish ? 'Escanear / introducir código' : 'Scan / enter code';
  String get eanBarcode =>
      _isSpanish ? 'EAN / código de barras' : 'EAN / barcode';
  String get typeOrScanBarcode =>
      _isSpanish
          ? 'Escribe el código o usa el escáner'
          : 'Type barcode or use scanner';
  String get enterBarcode => _isSpanish ? 'Introducir código' : 'Enter barcode';
  String get search => _isSpanish ? 'Buscar' : 'Search';
  String get barcodeExample =>
      _isSpanish ? 'ej. 8410188008736' : 'e.g. 8410188008736';
  String get noImageSelectedYet =>
      _isSpanish ? 'Aún no hay imagen seleccionada' : 'No image selected yet';
  String get takePhoto => _isSpanish ? 'Tomar foto' : 'Take photo';
  String get selectFromGallery =>
      _isSpanish ? 'Seleccionar de galería' : 'Select from gallery';
  String get selectImageFromDisk =>
      _isSpanish ? 'Seleccionar imagen del disco' : 'Select image from disk';
  String get selectImage => _isSpanish ? 'Seleccionar imagen' : 'Select image';
  String get detectFoods => _isSpanish ? 'Detectar alimentos' : 'Detect foods';
  String get detectingFoods =>
      _isSpanish ? 'Detectando alimentos...' : 'Detecting foods...';
  String get mealSummary => _isSpanish ? 'Resumen de comida' : 'Meal summary';
  String get mealDetail => _isSpanish ? 'Detalle de comida' : 'Meal detail';
  String get mealNotFound =>
      _isSpanish ? 'Comida no encontrada' : 'Meal not found';
  String get confirmDetectedFoods =>
      _isSpanish ? 'Confirmar alimentos detectados' : 'Confirm detected foods';
  String get confirmFoods =>
      _isSpanish ? 'Confirmar alimentos' : 'Confirm foods';
  String get mealStartedFromBarcode =>
      _isSpanish
          ? 'Comida iniciada desde código de barras/entrada manual.'
          : 'Meal started from barcode/manual entry.';
  String get mealSavedWithoutPhoto =>
      _isSpanish
          ? 'Comida guardada sin foto (código de barras/entrada manual).'
          : 'Meal saved without photo (barcode/manual entry).';
  String get dailyDetail => _isSpanish ? 'Detalle diario' : 'Daily detail';
  String get noMealsRegistered =>
      _isSpanish ? 'No hay comidas registradas' : 'No meals registered';
  String get noMealsRegisteredForDay =>
      _isSpanish
          ? 'No hay comidas registradas para este día.'
          : 'No meals registered for this day.';
  String get deleteMeal => _isSpanish ? 'Eliminar comida' : 'Delete meal';
  String get deleteMealPermanentRemoved =>
      _isSpanish
          ? 'Esta comida se eliminará permanentemente.'
          : 'This meal will be permanently removed.';
  String get deleteMealPermanentDeleted =>
      _isSpanish
          ? 'Esta comida se eliminará permanentemente.'
          : 'This meal will be permanently deleted.';
  String get scanBarcode => _isSpanish ? 'Escanear código' : 'Scan barcode';
  String get flash => _isSpanish ? 'Flash' : 'Flash';
  String get centerBarcodeInCamera =>
      _isSpanish
          ? 'Centra el código de barras dentro de la vista de la cámara.'
          : 'Center the barcode inside the camera view.';
  String get saveMeal => _isSpanish ? 'Guardar comida' : 'Save meal';
  String get saving => _isSpanish ? 'Guardando...' : 'Saving...';
  String get estimationDisclaimer =>
      _isSpanish
          ? 'Valores estimados: el reconocimiento de alimentos y las calorías no son precisos y no deben usarse como consejo médico o nutricional.'
          : 'Estimated values only: food recognition and calories are not precise and must not be used as medical or nutritional advice.';

  String mealsAndCalories(int mealsCount, double calories) {
    if (_isSpanish) {
      return '$mealsCount comidas | ${calories.toStringAsFixed(0)} kcal';
    }
    return '$mealsCount meals | ${calories.toStringAsFixed(0)} kcal';
  }

  String estimatedCalories(double calories) {
    if (_isSpanish) {
      return 'Calorías estimadas: ${calories.toStringAsFixed(0)} kcal';
    }
    return 'Estimated calories: ${calories.toStringAsFixed(0)} kcal';
  }

  String estimatedAndLikelyRange({
    required double total,
    required double lower,
    required double upper,
  }) {
    if (_isSpanish) {
      return 'Estimado: ${total.toStringAsFixed(0)} kcal, '
          'rango probable: ${lower.toStringAsFixed(0)}-${upper.toStringAsFixed(0)} kcal';
    }
    return 'Estimated: ${total.toStringAsFixed(0)} kcal, '
        'likely range: ${lower.toStringAsFixed(0)}-${upper.toStringAsFixed(0)} kcal';
  }

  String failedToProcessImage(Object error) {
    if (_isSpanish) {
      return 'No se pudo procesar la imagen seleccionada: $error';
    }
    return 'Failed to process the selected image: $error';
  }

  String failedToLookupBarcode(Object error) {
    if (_isSpanish) {
      return 'No se pudo buscar el código de barras: $error';
    }
    return 'Failed to lookup barcode: $error';
  }

  String failedToSaveMeal(Object error) {
    if (_isSpanish) {
      return 'No se pudo guardar la comida: $error';
    }
    return 'Failed to save meal: $error';
  }

  String get barcodeNotFound =>
      _isSpanish
          ? 'Código no encontrado en la base local ni en Open Food Facts.'
          : 'Barcode not found in local database or Open Food Facts.';

  String get addAtLeastOneFoodItem =>
      _isSpanish
          ? 'Añade al menos un alimento.'
          : 'Add at least one food item.';

  String mealTypeLabel(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
      case 'desayuno':
        return _isSpanish ? 'Desayuno' : 'Breakfast';
      case 'lunch':
      case 'comida':
        return _isSpanish ? 'Comida' : 'Lunch';
      case 'dinner':
      case 'cena':
        return _isSpanish ? 'Cena' : 'Dinner';
      case 'snack':
      case 'tentempié':
      case 'tentempie':
        return _isSpanish ? 'Tentempié' : 'Snack';
      default:
        return _isSpanish ? 'Otro' : 'Other';
    }
  }

  String portionLabel(String portion) {
    switch (portion.toLowerCase()) {
      case 'small':
        return _isSpanish ? 'pequeña' : 'small';
      case 'medium':
        return _isSpanish ? 'mediana' : 'medium';
      case 'large':
        return _isSpanish ? 'grande' : 'large';
      default:
        return _isSpanish ? 'personalizada' : 'custom';
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode.toLowerCase().startsWith('en') ||
        locale.languageCode.toLowerCase().startsWith('es');
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
