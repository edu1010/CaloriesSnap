import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/food_item.dart';
import '../../models/nutrition_food.dart';
import '../../services/barcode/open_food_facts_service.dart';
import '../../services/food_detection/food_detection_service.dart';
import '../../services/image/image_storage_service.dart';
import '../../services/nutrition/calorie_calculator.dart';
import 'barcode_scanner_screen.dart';
import 'food_confirmation_screen.dart';

class RegisterMealScreen extends StatefulWidget {
  const RegisterMealScreen({
    super.key,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.foodDetectionService,
    required this.openFoodFactsService,
    required this.imageStorageService,
    required this.calorieCalculator,
  });

  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final FoodDetectionService foodDetectionService;
  final OpenFoodFactsService openFoodFactsService;
  final ImageStorageService imageStorageService;
  final CalorieCalculator calorieCalculator;

  @override
  State<RegisterMealScreen> createState() => _RegisterMealScreenState();
}

class _RegisterMealScreenState extends State<RegisterMealScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _barcodeController = TextEditingController();

  String? _selectedImagePath;
  bool _isDetecting = false;
  bool _isBarcodeLookup = false;
  String? _errorText;

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _pickFromCamera() async {
    final file = await _imagePicker.pickImage(source: ImageSource.camera);
    if (file == null) {
      return;
    }
    setState(() {
      _selectedImagePath = file.path;
      _errorText = null;
    });
  }

  Future<void> _pickFromGallery() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return;
    }
    setState(() {
      _selectedImagePath = file.path;
      _errorText = null;
    });
  }

  Future<void> _pickFromDisk() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    setState(() {
      _selectedImagePath = path;
      _errorText = null;
    });
  }

  Future<void> _detectFoods() async {
    if (_selectedImagePath == null) {
      return;
    }

    setState(() {
      _isDetecting = true;
      _errorText = null;
    });

    try {
      final storedPath = await widget.imageStorageService.copyToAppStorage(
        _selectedImagePath!,
      );
      final detected = await widget.foodDetectionService.detectFoods(
        storedPath,
      );

      final foods =
          detected.map((item) {
            final calories = widget.calorieCalculator.calculateFoodCalories(
              item.suggestedGrams,
              item.kcalPer100g,
            );
            return FoodItem(
              name: item.name,
              grams: item.suggestedGrams,
              kcalPer100g: item.kcalPer100g,
              calculatedKcal: calories,
            );
          }).toList();

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => FoodConfirmationScreen(
                imagePath: storedPath,
                initialFoods: foods,
                mealRepository: widget.mealRepository,
                nutritionRepository: widget.nutritionRepository,
                calorieCalculator: widget.calorieCalculator,
              ),
        ),
      );
    } catch (error) {
      setState(() {
        _errorText = 'Failed to process the selected image: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }

  bool get _supportsCameraBarcodeScanner {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<String?> _askBarcodeManually() async {
    _barcodeController.text = _barcodeController.text.trim();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter barcode'),
          content: TextField(
            controller: _barcodeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'EAN / barcode',
              hintText: 'e.g. 8410188008736',
            ),
            onSubmitted: (value) {
              Navigator.of(context).pop(value.trim());
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, _barcodeController.text.trim());
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBarcodeFlow() async {
    String? barcode;
    if (_supportsCameraBarcodeScanner) {
      barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const BarcodeScannerScreen()),
      );
      barcode = barcode?.trim();
      if (barcode == null || barcode.isEmpty) {
        barcode = await _askBarcodeManually();
      }
    } else {
      barcode = await _askBarcodeManually();
    }

    if (barcode == null || barcode.trim().isEmpty) {
      return;
    }

    await _lookupBarcodeAndContinue(barcode);
  }

  Future<void> _lookupBarcodeAndContinue(String barcodeInput) async {
    setState(() {
      _isBarcodeLookup = true;
      _errorText = null;
    });

    try {
      final localMatch = widget.nutritionRepository.findByBarcode(barcodeInput);
      if (localMatch != null) {
        await _openFoodConfirmationFromNutrition(localMatch);
        return;
      }

      final offProduct = await widget.openFoodFactsService.lookupByBarcode(
        barcodeInput,
      );
      if (offProduct == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Barcode not found in local database or Open Food Facts.',
            ),
          ),
        );
        return;
      }

      final productName =
          offProduct.brand == null
              ? offProduct.name
              : '${offProduct.name} (${offProduct.brand})';
      final grams = 100.0;
      final food = FoodItem(
        name: productName,
        grams: grams,
        kcalPer100g: offProduct.kcalPer100g,
        calculatedKcal: widget.calorieCalculator.calculateFoodCalories(
          grams,
          offProduct.kcalPer100g,
        ),
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => FoodConfirmationScreen(
                imagePath: null,
                initialFoods: <FoodItem>[food],
                mealRepository: widget.mealRepository,
                nutritionRepository: widget.nutritionRepository,
                calorieCalculator: widget.calorieCalculator,
              ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = 'Failed to lookup barcode: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBarcodeLookup = false;
        });
      }
    }
  }

  Future<void> _openFoodConfirmationFromNutrition(
    NutritionFood nutrition,
  ) async {
    final grams = nutrition.defaultGramsMedium;
    final food = FoodItem(
      name: nutrition.name,
      grams: grams,
      kcalPer100g: nutrition.kcalPer100g,
      calculatedKcal: widget.calorieCalculator.calculateFoodCalories(
        grams,
        nutrition.kcalPer100g,
      ),
    );

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => FoodConfirmationScreen(
              imagePath: null,
              initialFoods: <FoodItem>[food],
              mealRepository: widget.mealRepository,
              nutritionRepository: widget.nutritionRepository,
              calorieCalculator: widget.calorieCalculator,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final isWindows = Platform.isWindows;
    final canSubmitBarcode = !_isDetecting && !_isBarcodeLookup;

    return Scaffold(
      appBar: AppBar(title: const Text('Register meal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                if (isAndroid)
                  FilledButton.icon(
                    onPressed: _pickFromCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                if (isAndroid)
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Select from gallery'),
                  ),
                if (isWindows)
                  FilledButton.icon(
                    onPressed: _pickFromDisk,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Select image from disk'),
                  ),
                if (!isAndroid && !isWindows)
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Select image'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedImagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.file(
                    File(_selectedImagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                height: 240,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                child: const Text('No image selected yet'),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Alternative: barcode',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _barcodeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'EAN / barcode',
                        hintText: 'Type barcode or use scanner',
                      ),
                      onSubmitted: (_) {
                        if (!canSubmitBarcode) {
                          return;
                        }
                        _lookupBarcodeAndContinue(_barcodeController.text);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed:
                              canSubmitBarcode
                                  ? () => _lookupBarcodeAndContinue(
                                    _barcodeController.text,
                                  )
                                  : null,
                          icon:
                              _isBarcodeLookup
                                  ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.qr_code_2),
                          label: Text(
                            _isBarcodeLookup ? 'Searching...' : 'Use barcode',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: canSubmitBarcode ? _openBarcodeFlow : null,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: Text(
                            _supportsCameraBarcodeScanner
                                ? 'Scan with camera'
                                : 'Scan / enter code',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.estimationDisclaimer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed:
                  _selectedImagePath == null || _isDetecting || _isBarcodeLookup
                      ? null
                      : _detectFoods,
              icon:
                  _isDetecting
                      ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.auto_awesome_outlined),
              label: Text(_isDetecting ? 'Detecting foods...' : 'Detect foods'),
            ),
          ],
        ),
      ),
    );
  }
}
