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
          ? 'Los modelos de visión pueden identificar varios alimentos en un plato y estimar sus raciones. Una vez descargados, funcionan sin conexión y analizan las fotos en este dispositivo.'
          : 'Vision models can identify several foods on a plate and estimate their portions. Once downloaded, they run offline and analyse photos on this device.';
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

  String get goalsAndActivity =>
      _isSpanish ? 'Objetivos y actividad' : 'Goals & activity';
  String get refresh => _isSpanish ? 'Actualizar' : 'Refresh';
  String get retry => _isSpanish ? 'Reintentar' : 'Try again';
  String get close => _isSpanish ? 'Cerrar' : 'Close';
  String get notSet => _isSpanish ? 'Sin definir' : 'Not set';
  String get noData => _isSpanish ? 'Sin datos' : 'No data';
  String get intakeGoals =>
      _isSpanish ? 'Objetivos de ingesta' : 'Intake goals';
  String get dailyGoal => _isSpanish ? 'Objetivo diario' : 'Daily goal';
  String get weeklyGoal => _isSpanish ? 'Objetivo semanal' : 'Weekly goal';
  String get editGoals => _isSpanish ? 'Editar objetivos' : 'Edit goals';
  String get goalsIndependentHint =>
      _isSpanish
          ? 'Los dos objetivos son opcionales e independientes: el semanal no se calcula a partir del diario.'
          : 'Both goals are optional and independent: the weekly one is not calculated from the daily one.';
  String get goalsEditorHint =>
      _isSpanish
          ? 'Deja un campo vacío para quitar ese objetivo. CalorieSnap no recomienda ninguna cifra.'
          : 'Leave a field empty to remove that goal. CalorieSnap does not recommend any figure.';
  String get dailyGoalFieldLabel =>
      _isSpanish ? 'Objetivo diario (kcal)' : 'Daily goal (kcal)';
  String get weeklyGoalFieldLabel =>
      _isSpanish ? 'Objetivo semanal (kcal)' : 'Weekly goal (kcal)';
  String get goalsSaved => _isSpanish ? 'Objetivos guardados.' : 'Goals saved.';
  String get consumed => _isSpanish ? 'Consumido' : 'Consumed';
  String get noDailyGoalSet =>
      _isSpanish ? 'Sin objetivo diario definido.' : 'No daily goal set.';
  String get noWeeklyGoalSet =>
      _isSpanish ? 'Sin objetivo semanal definido.' : 'No weekly goal set.';
  String get activeBurned => _isSpanish ? 'Gasto activo' : 'Active burned';
  String get totalBurned => _isSpanish ? 'Gasto total' : 'Total burned';
  String get netEnergy => _isSpanish ? 'Balance neto' : 'Net energy';
  String get netEnergyExplanation =>
      _isSpanish
          ? 'Consumido menos gasto total'
          : 'Consumed minus total burned';
  String get netEnergyUnavailable =>
      _isSpanish
          ? 'Balance neto no disponible: se desconoce el gasto total.'
          : 'Net energy unavailable: total expenditure unknown.';
  String get steps => _isSpanish ? 'Pasos' : 'Steps';
  String get distance => _isSpanish ? 'Distancia' : 'Distance';
  String get activeMinutes => _isSpanish ? 'Minutos activos' : 'Active minutes';
  String get noActivityToday =>
      _isSpanish
          ? 'No hay datos de actividad para hoy'
          : 'No activity data for today';
  String get noActivityHint =>
      _isSpanish
          ? 'No se asume ningún valor. Introduce la actividad a mano, sincroniza con Health Connect o importa un CSV.'
          : 'Nothing is assumed. Enter your activity manually, synchronise with Health Connect or import a CSV.';
  String get enterManually =>
      _isSpanish ? 'Introducir a mano' : 'Enter manually';
  String get editManualEntry =>
      _isSpanish ? 'Editar entrada manual' : 'Edit manual entry';
  String get sourceManual => _isSpanish ? 'Manual' : 'Manual';
  String get sourceHealthConnect =>
      _isSpanish ? 'Health Connect' : 'Health Connect';
  String get sourceCsvImport => _isSpanish ? 'Importación CSV' : 'CSV import';
  String get manualReplacesImportedNote =>
      _isSpanish
          ? 'Una entrada manual se usa en lugar de los datos importados de ese día; nunca se suman.'
          : 'A manual entry is used instead of imported data for that day; they are never added together.';
  String get week => _isSpanish ? 'Semana' : 'Week';
  String get previousWeek => _isSpanish ? 'Semana anterior' : 'Previous week';
  String get nextWeek => _isSpanish ? 'Semana siguiente' : 'Next week';
  String get dayColumn => _isSpanish ? 'Día' : 'Day';
  String get consumedKcalColumn =>
      _isSpanish ? 'Consumido (kcal)' : 'Consumed (kcal)';
  String get burnedKcalColumn =>
      _isSpanish ? 'Gasto activo (kcal)' : 'Active burned (kcal)';
  String get tapDayToEditHint =>
      _isSpanish
          ? 'Toca un día para introducir o editar su actividad manual. «—» significa que no hay datos.'
          : 'Tap a day to enter or edit its manual activity. "—" means there is no data.';
  String get futureDay => _isSpanish ? 'día futuro' : 'future day';
  String get activeKcalField =>
      _isSpanish ? 'Gasto activo (kcal)' : 'Active burned (kcal)';
  String get totalKcalField =>
      _isSpanish ? 'Gasto total (kcal)' : 'Total burned (kcal)';
  String get totalKcalHelper =>
      _isSpanish
          ? 'Solo si tu dispositivo indica el gasto total'
          : 'Only if your device reports total expenditure';
  String get distanceKmField => _isSpanish ? 'Distancia (km)' : 'Distance (km)';
  String get manualAllOptionalHint =>
      _isSpanish
          ? 'Todos los campos son opcionales, pero rellena al menos uno. Lo que dejes vacío no se guarda como 0.'
          : 'Every field is optional, but fill in at least one. Anything left empty is not stored as 0.';
  String get manualNeedsOneValue =>
      _isSpanish ? 'Introduce al menos un valor.' : 'Enter at least one value.';
  String get invalidWholeNumber =>
      _isSpanish
          ? 'Introduce un número entero igual o mayor que 0.'
          : 'Enter a whole number, 0 or more.';
  String get invalidDecimalNumber =>
      _isSpanish
          ? 'Introduce un número igual o mayor que 0.'
          : 'Enter a number, 0 or more.';
  String get valueOutOfRange =>
      _isSpanish
          ? 'Valor fuera del rango admitido.'
          : 'Value outside the accepted range.';
  String get activeExceedsTotal =>
      _isSpanish
          ? 'El gasto activo no puede superar el gasto total.'
          : 'Active burned cannot exceed total burned.';
  String get manualFallbackGenericNote =>
      _isSpanish
          ? 'Si eliminas la entrada manual, se usarán los datos importados de ese día, si existen.'
          : 'If you delete the manual entry, imported data for that day is used again, if there is any.';
  String get deleteManualEntry =>
      _isSpanish ? 'Eliminar entrada manual' : 'Delete manual entry';
  String get deleteManualEntryConfirm =>
      _isSpanish
          ? 'Se eliminará la entrada manual de este día. Si no hay datos importados, el día quedará sin datos de actividad.'
          : 'The manual entry for this day will be deleted. If there is no imported data, the day will have no activity data.';
  String get manualEntrySaved =>
      _isSpanish ? 'Entrada manual guardada.' : 'Manual entry saved.';
  String get manualEntryDeleted =>
      _isSpanish ? 'Entrada manual eliminada.' : 'Manual entry deleted.';
  String get healthConnect => _isSpanish ? 'Health Connect' : 'Health Connect';
  String get synchroniseNow =>
      _isSpanish ? 'Sincronizar ahora' : 'Synchronise now';
  String get synchronising => _isSpanish ? 'Sincronizando…' : 'Synchronising…';
  String get checkingAvailability =>
      _isSpanish ? 'Comprobando Health Connect…' : 'Checking Health Connect…';
  String get syncCheckFailed =>
      _isSpanish
          ? 'No se pudo comprobar si Health Connect está disponible.'
          : 'Could not check whether Health Connect is available.';
  String get syncUnsupportedPlatform =>
      _isSpanish
          ? 'La sincronización con Health Connect solo está disponible en Android. En este dispositivo puedes introducir la actividad a mano o importar un CSV.'
          : 'Health Connect synchronisation is only available on Android. On this device you can enter activity manually or import a CSV.';
  String get syncProviderNotInstalled =>
      _isSpanish
          ? 'Health Connect no está instalado en este teléfono.'
          : 'Health Connect is not installed on this phone.';
  String get syncProviderUpdateRequired =>
      _isSpanish
          ? 'Health Connect necesita actualizarse para poder leer los datos.'
          : 'Health Connect needs an update before data can be read.';
  String get installHealthConnect =>
      _isSpanish ? 'Instalar Health Connect' : 'Install Health Connect';
  String get updateHealthConnect =>
      _isSpanish ? 'Actualizar Health Connect' : 'Update Health Connect';
  String get openHealthConnect =>
      _isSpanish ? 'Abrir Health Connect' : 'Open Health Connect';
  String get couldNotOpenHealthConnect =>
      _isSpanish
          ? 'No se pudo abrir Health Connect.'
          : 'Could not open Health Connect.';
  String get syncPermissionDenied =>
      _isSpanish
          ? 'Permiso denegado: CalorieSnap no puede leer Health Connect hasta que lo concedas. Vuelve a sincronizar o abre Health Connect para dar permiso.'
          : 'Permission denied: CalorieSnap cannot read Health Connect until you grant it. Synchronise again or open Health Connect to grant access.';
  String get neverSynchronised =>
      _isSpanish ? 'Nunca sincronizado' : 'Never synchronised';
  String get whichApps => _isSpanish ? '¿Qué aplicaciones?' : 'Which apps?';
  String get whichAppsBody =>
      _isSpanish
          ? 'Mi Fitness (Xiaomi): Perfil → Datos de terceros → Health Connect. Strava: Tú → Ajustes → Administrar aplicaciones y dispositivos → Health Connect. Activa los permisos para compartir actividad. Para Huawei Health hace falta una aplicación puente compatible o importar un CSV convertido al formato indicado. CalorieSnap lee los datos compartidos con Health Connect en este teléfono; no conecta directamente con las cuentas de estos servicios.'
          : 'Mi Fitness (Xiaomi): Profile → Third-party data → Health Connect. Strava: You → Settings → Manage Apps and Devices → Health Connect. Allow activity sharing. Huawei Health needs a compatible bridge app or a CSV converted to the documented format. CalorieSnap reads data shared with Health Connect on this phone; it does not connect directly to these service accounts.';
  String get importCsv => _isSpanish ? 'Importar CSV' : 'Import CSV';
  String get importCsvDescription =>
      _isSpanish
          ? 'Importa un archivo CSV con una fila por día, la fecha y al menos un dato de actividad. Deja vacías las columnas que no tengas.'
          : 'Import a CSV file with one row per day, its date and at least one activity value. Leave columns you do not have empty.';
  String get chooseCsvFile =>
      _isSpanish ? 'Elegir archivo CSV' : 'Choose CSV file';
  String get csvTooLarge =>
      _isSpanish
          ? 'El archivo supera los 2 MB y no se ha importado.'
          : 'The file is larger than 2 MB and was not imported.';
  String get csvNotUtf8 =>
      _isSpanish
          ? 'El archivo no es texto UTF-8 válido.'
          : 'The file is not valid UTF-8 text.';
  String get csvInvalidHeaderTitle =>
      _isSpanish ? 'Cabecera no válida' : 'Invalid header';
  String get csvInvalidHeaderBody =>
      _isSpanish
          ? 'La primera línea del archivo debe contener estas columnas:'
          : 'The first line of the file must contain these columns:';
  String get csvSummaryTitle =>
      _isSpanish ? 'Confirmar importación' : 'Confirm import';
  String get csvNoValidRows =>
      _isSpanish
          ? 'El archivo no contiene ningún día válido.'
          : 'The file contains no valid days.';
  String get csvPrecedenceNote =>
      _isSpanish
          ? 'Los días que ya tengan una entrada manual o datos de Health Connect seguirán usando esos datos. Importar de nuevo una fecha sustituye su registro CSV anterior.'
          : 'Days that already have a manual entry or Health Connect data keep using that data. Importing a date again replaces its previous CSV record.';
  String get importAction => _isSpanish ? 'Importar' : 'Import';

  String kcalAmount(String amount) => '$amount kcal';

  String distanceKm(String km) => '$km km';

  String minutesAmount(String minutes) => '$minutes min';

  String dateRange(String start, String end) => '$start – $end';

  String failedToLoadDashboard(Object error) =>
      _isSpanish
          ? 'No se pudieron cargar los datos: $error'
          : 'Could not load the data: $error';

  String failedToSave(Object error) =>
      _isSpanish ? 'No se pudo guardar: $error' : 'Could not save: $error';

  String goalInvalid(String max) =>
      _isSpanish
          ? 'Introduce un número entero mayor que 0 y como máximo $max.'
          : 'Enter a whole number greater than 0 and at most $max.';

  String remainingKcal(String amount) =>
      _isSpanish ? 'Quedan $amount kcal' : '$amount kcal left';

  String overGoalKcal(String amount) =>
      _isSpanish
          ? 'Objetivo superado en $amount kcal'
          : 'Over goal by $amount kcal';

  String consumedOfGoal(String consumed, String goal) =>
      _isSpanish ? '$consumed de $goal kcal' : '$consumed of $goal kcal';

  String dailyGoalWithValue(String goal) =>
      _isSpanish ? 'Objetivo diario: $goal kcal' : 'Daily goal: $goal kcal';

  String mealsCountLabel(int count) {
    if (_isSpanish) {
      return count == 1 ? '1 comida' : '$count comidas';
    }
    return count == 1 ? '1 meal' : '$count meals';
  }

  String todayWithDate(String date) =>
      _isSpanish ? 'Hoy · $date' : 'Today · $date';

  String dataSource(String source) =>
      _isSpanish ? 'Origen de los datos: $source' : 'Data source: $source';

  String dataOrigin(String origin) =>
      _isSpanish ? 'Procedencia: $origin' : 'From: $origin';

  String mealsLoggedOnDays(int days) =>
      _isSpanish
          ? 'Comidas registradas en $days de 7 días'
          : 'Meals logged on $days of 7 days';

  String dataForDays(int days, int elapsedDays) =>
      _isSpanish
          ? 'Datos de $days de $elapsedDays días'
          : 'Data for $days of $elapsedDays days';

  String netPartialDays(int days, int elapsedDays) =>
      _isSpanish
          ? 'Parcial: solo $days de $elapsedDays días con gasto total'
          : 'Partial: over $days of $elapsedDays days with total expenditure';

  String netCompleteDays(int elapsedDays) {
    if (_isSpanish) {
      return elapsedDays == 1
          ? 'Incluye el único día transcurrido'
          : 'Incluye los $elapsedDays días transcurridos';
    }
    return elapsedDays == 1
        ? 'Covers the only elapsed day'
        : 'Covers all $elapsedDays elapsed days';
  }

  String totalOnly(String amount) => '$amount total';

  String dayRowSemantics(String day, String consumed, String burned) =>
      _isSpanish
          ? '$day: consumido $consumed, gasto activo $burned'
          : '$day: consumed $consumed, active burned $burned';

  String manualActivityTitle(String date) =>
      _isSpanish ? 'Actividad manual · $date' : 'Manual activity · $date';

  String manualFallbackNote(String source) =>
      _isSpanish
          ? 'Este día también tiene datos de $source. Si eliminas la entrada manual, se volverán a usar.'
          : 'This day also has data from $source. If you delete the manual entry, that data is used again.';

  String syncDescription(int days) =>
      _isSpanish
          ? 'Lee los últimos $days días solo cuando pulsas «Sincronizar ahora». No se lee nada en segundo plano.'
          : 'Reads the last $days days only when you tap "Synchronise now". Nothing is read in the background.';

  String syncSuccess(int days) {
    if (days == 0) {
      return _isSpanish
          ? 'Sincronización completada: Health Connect no devolvió datos.'
          : 'Synchronisation finished: Health Connect returned no data.';
    }
    if (_isSpanish) {
      return days == 1
          ? 'Sincronización completada: datos de 1 día.'
          : 'Sincronización completada: datos de $days días.';
    }
    return days == 1
        ? 'Synchronisation finished: data for 1 day.'
        : 'Synchronisation finished: data for $days days.';
  }

  String syncFailed(String? message) {
    if (message == null || message.isEmpty) {
      return _isSpanish
          ? 'La sincronización ha fallado.'
          : 'Synchronisation failed.';
    }
    return _isSpanish
        ? 'La sincronización ha fallado: $message'
        : 'Synchronisation failed: $message';
  }

  String lastSynchronised(String dateTime) =>
      _isSpanish
          ? 'Última sincronización: $dateTime'
          : 'Last synchronised: $dateTime';

  String lastAttemptFailed(String reason) =>
      _isSpanish
          ? 'El último intento falló. $reason'
          : 'The last attempt failed. $reason';

  String csvExpectedColumns(String columns) =>
      _isSpanish ? 'Columnas: $columns' : 'Columns: $columns';

  String csvUnreadable(Object error) =>
      _isSpanish
          ? 'No se pudo leer el archivo: $error'
          : 'Could not read the file: $error';

  String csvFileName(String name) =>
      _isSpanish ? 'Archivo: $name' : 'File: $name';

  String csvValidDays(int count) {
    if (_isSpanish) {
      return count == 1 ? '1 día válido' : '$count días válidos';
    }
    return count == 1 ? '1 valid day' : '$count valid days';
  }

  String csvRejectedRows(int count) {
    if (_isSpanish) {
      return count == 1 ? '1 fila rechazada' : '$count filas rechazadas';
    }
    return count == 1 ? '1 row rejected' : '$count rows rejected';
  }

  String csvRowError(int line, String reason) =>
      _isSpanish ? 'Línea $line: $reason' : 'Line $line: $reason';

  String csvMoreErrors(int count) =>
      _isSpanish ? '… y $count más' : '… and $count more';

  String csvImported(int count) {
    if (_isSpanish) {
      return count == 1
          ? 'Se ha importado 1 día.'
          : 'Se han importado $count días.';
    }
    return count == 1 ? 'Imported 1 day.' : 'Imported $count days.';
  }

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

  // --- Dish description and ingredient search -------------------------------

  String get dishDescription =>
      _isSpanish ? 'Describe el plato (opcional)' : 'Describe the dish (optional)';
  String get dishDescriptionHint =>
      _isSpanish
          ? 'Ej.: arroz frito con pollo a la plancha y ensalada'
          : 'E.g. fried rice with grilled chicken and salad';
  String get dishDescriptionHelp =>
      _isSpanish
          ? 'Ayuda a la IA a acertar: qué es, cómo está cocinado, aceite, salsas o lo que no se ve en la foto.'
          : 'Helps the AI get it right: what it is, how it was cooked, oil, sauces or anything the photo does not show.';
  String get missingIngredient =>
      _isSpanish ? '¿Falta algún ingrediente?' : 'Missing an ingredient?';
  String get addIngredient =>
      _isSpanish ? 'Buscar y añadir' : 'Search and add';
  String get fromYourDescription =>
      _isSpanish
          ? 'Mencionado en tu descripción (toca para añadir):'
          : 'Mentioned in your description (tap to add):';
  String get searchFoodHint =>
      _isSpanish
          ? 'Busca un alimento: arroz, pollo, aceite…'
          : 'Search a food: rice, chicken, oil…';
  String get noFoodResults =>
      _isSpanish
          ? 'Sin resultados. Puedes añadirlo como alimento personalizado.'
          : 'No results. You can add it as a custom food.';
  String get preparation => _isSpanish ? 'Preparación' : 'Preparation';
  String get per100g => _isSpanish ? 'Por 100 g' : 'Per 100 g';
  String get protein => _isSpanish ? 'Proteínas' : 'Protein';
  String get carbs => _isSpanish ? 'Hidratos' : 'Carbs';
  String get fat => _isSpanish ? 'Grasas' : 'Fat';
  String get grams => _isSpanish ? 'Gramos' : 'Grams';
  String get dish => _isSpanish ? 'Plato' : 'Dish';
  String get addToMeal => _isSpanish ? 'Añadir a la comida' : 'Add to meal';
  /// Provenance of one ingredient variant's values.
  String nutritionSourceNote({int? ciqualCode, int? addedOilGrams}) {
    if (ciqualCode != null && addedOilGrams != null) {
      return _isSpanish
          ? 'Estimación: alimento $ciqualCode de CIQUAL 2020 (ANSES) con $addedOilGrams g de aceite de oliva por 100 g.'
          : 'Estimate: CIQUAL 2020 (ANSES) food $ciqualCode with $addedOilGrams g of olive oil per 100 g.';
    }
    if (ciqualCode != null) {
      return _isSpanish
          ? 'Fuente: tabla oficial CIQUAL 2020 (ANSES), alimento $ciqualCode.'
          : 'Source: official CIQUAL 2020 table (ANSES), food $ciqualCode.';
    }
    return _isSpanish
        ? 'Estimación propia: este alimento no figura en CIQUAL 2020.'
        : 'Own estimate: this food is not in CIQUAL 2020.';
  }
  String portionEnergy(double grams, double kcal) =>
      _isSpanish
          ? 'Tu ración: ${grams.toStringAsFixed(0)} g · ${kcal.toStringAsFixed(0)} kcal'
          : 'Your portion: ${grams.toStringAsFixed(0)} g · ${kcal.toStringAsFixed(0)} kcal';

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
