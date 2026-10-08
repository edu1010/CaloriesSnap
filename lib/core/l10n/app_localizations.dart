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
  String get possibleDish =>
      _isSpanish ? '¿Qué plato es?' : 'Which dish is it?';
  String get photoPortionHint =>
      _isSpanish
          ? 'La foto sugiere el plato, pero no mide su peso. Ajusta los gramos de tu ración y añade por separado acompañamientos, aceite y salsas.'
          : 'The photo suggests a dish but cannot weigh it. Adjust your portion in grams and add sides, oil and sauces separately.';
  String get uncertainDish =>
      _isSpanish
          ? 'Identificación dudosa: elige un plato o añádelo manualmente.'
          : 'Uncertain identification: choose a dish or add it manually.';
  String get noReliableDish =>
      _isSpanish
          ? 'No se ha identificado un plato con suficiente seguridad. Prueba una foto más cercana o añade el alimento.'
          : 'No dish identified reliably. Try a closer photo or add a food.';
  String get alternativeDishes =>
      _isSpanish
          ? 'Son alternativas del mismo plato; solo se contabiliza la que elijas.'
          : 'These are alternatives for the same dish; only your selection is counted.';
  String get invalidFoodValues =>
      _isSpanish
          ? 'Indica un nombre, gramos mayores que cero y kcal/100 g entre 0 y 1000.'
          : 'Enter a name, grams greater than zero and kcal/100 g between 0 and 1000.';
  String get modelScore => _isSpanish ? 'Puntuación del modelo' : 'Model score';
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

  String get localAi => _isSpanish ? 'IA local' : 'On-device AI';
  String get localAiIntro =>
      _isSpanish
          ? 'Un modelo de visión (Qwen) describe el plato completo: reconoce cualquier comida, separa sus componentes y estima los gramos. Se descarga una vez y después funciona sin conexión; tus fotos no salen del dispositivo.'
          : 'A vision model (Qwen) describes the whole plate: it recognises any food, separates its components and estimates grams. It is downloaded once and then works offline; your photos never leave the device.';
  String get localAiSpeedNote =>
      _isSpanish
          ? 'Analizar una foto tarda bastante más que el clasificador rápido, sobre todo en móviles modestos.'
          : 'Analysing a photo takes noticeably longer than the fast classifier, especially on modest phones.';
  String get classifierOnly =>
      _isSpanish ? 'Solo clasificador rápido' : 'Fast classifier only';
  String get classifierOnlyDescription =>
      _isSpanish
          ? 'Instantáneo, pero limitado a 116 platos y a un alimento por foto.'
          : 'Instant, but limited to 116 dishes and one food per photo.';
  String get lightModelDescription =>
      _isSpanish
          ? 'Ligero: para la mayoría de móviles.'
          : 'Light: for most phones.';
  String get preciseModelDescription =>
      _isSpanish
          ? 'Más preciso: para móviles con 8 GB de RAM o más.'
          : 'More accurate: for phones with 8 GB of RAM or more.';
  String get inUse => _isSpanish ? 'En uso' : 'In use';
  String get use => _isSpanish ? 'Usar' : 'Use';
  String get cancelDownload =>
      _isSpanish ? 'Cancelar descarga' : 'Cancel download';
  String get verifyingDownload =>
      _isSpanish ? 'Verificando la descarga...' : 'Verifying download...';
  String get downloadOverWifi =>
      _isSpanish
          ? 'Descarga grande: mejor con wifi.'
          : 'Large download: Wi-Fi recommended.';
  String get loadingAiModel =>
      _isSpanish ? 'Cargando el modelo de IA...' : 'Loading the AI model...';
  String get analyzingWithAi =>
      _isSpanish
          ? 'Analizando el plato con IA local...'
          : 'Analysing the plate with on-device AI...';
  String get aiPortionHint =>
      _isSpanish
          ? 'Los gramos son una estimación visual del modelo. Revísalos y ajusta lo que no cuadre.'
          : 'Grams are a visual estimate by the model. Review them and adjust anything that looks off.';
  String get aiFallbackNotice =>
      _isSpanish
          ? 'La IA local no pudo analizar esta foto; se muestra el resultado del clasificador rápido.'
          : 'On-device AI could not analyse this photo; showing the fast classifier result.';

  String downloadModel(String size) =>
      _isSpanish ? 'Descargar ($size)' : 'Download ($size)';

  String downloadingModel(int percent) =>
      _isSpanish ? 'Descargando... $percent %' : 'Downloading... $percent%';

  String downloadFailed(Object error) =>
      _isSpanish
          ? 'No se pudo descargar el modelo: $error'
          : 'Could not download the model: $error';

  String lowMemoryWarning(int requiredGb, int deviceGb) =>
      _isSpanish
          ? 'Este dispositivo tiene unos $deviceGb GB de RAM y el modelo recomienda $requiredGb GB: puede ir lento o cerrarse.'
          : 'This device has about $deviceGb GB of RAM and the model recommends $requiredGb GB: it may be slow or get closed.';

  String analyzedByAi(String dish) =>
      _isSpanish ? 'IA local: $dish' : 'On-device AI: $dish';

  String aiEstimatedEnergy(String foods) =>
      _isSpanish
          ? 'Sin datos en la tabla nutricional; las kcal/100 g son una estimación del modelo: $foods.'
          : 'Not in the nutrition table; kcal/100 g are estimated by the model: $foods.';

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
