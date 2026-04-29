import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../models/food_item.dart';
import '../../services/food_detection/food_detection_service.dart';
import '../../services/image/image_storage_service.dart';
import '../../services/nutrition/calorie_calculator.dart';
import 'food_confirmation_screen.dart';

class RegisterMealScreen extends StatefulWidget {
  const RegisterMealScreen({
    super.key,
    required this.mealRepository,
    required this.nutritionRepository,
    required this.foodDetectionService,
    required this.imageStorageService,
    required this.calorieCalculator,
  });

  final MealRepository mealRepository;
  final NutritionRepository nutritionRepository;
  final FoodDetectionService foodDetectionService;
  final ImageStorageService imageStorageService;
  final CalorieCalculator calorieCalculator;

  @override
  State<RegisterMealScreen> createState() => _RegisterMealScreenState();
}

class _RegisterMealScreenState extends State<RegisterMealScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  String? _selectedImagePath;
  bool _isDetecting = false;
  String? _errorText;

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
      final detected = await widget.foodDetectionService.detectFoods(storedPath);

      final foods = detected.map((item) {
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
          builder: (_) => FoodConfirmationScreen(
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

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final isWindows = Platform.isWindows;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register meal'),
      ),
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
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                child: const Text('No image selected yet'),
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
              onPressed: _selectedImagePath == null || _isDetecting
                  ? null
                  : _detectFoods,
              icon: _isDetecting
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
