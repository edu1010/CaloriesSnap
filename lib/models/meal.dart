import 'food_item.dart';

class Meal {
  const Meal({
    this.id,
    required this.dateTime,
    required this.mealType,
    this.imagePath,
    required this.foods,
    required this.totalKcal,
    required this.lowerEstimateKcal,
    required this.upperEstimateKcal,
    required this.notes,
  });

  final int? id;
  final DateTime dateTime;
  final String mealType;
  final String? imagePath;
  final List<FoodItem> foods;
  final double totalKcal;
  final double lowerEstimateKcal;
  final double upperEstimateKcal;
  final String notes;

  Meal copyWith({
    int? id,
    DateTime? dateTime,
    String? mealType,
    String? imagePath,
    List<FoodItem>? foods,
    double? totalKcal,
    double? lowerEstimateKcal,
    double? upperEstimateKcal,
    String? notes,
  }) {
    return Meal(
      id: id ?? this.id,
      dateTime: dateTime ?? this.dateTime,
      mealType: mealType ?? this.mealType,
      imagePath: imagePath ?? this.imagePath,
      foods: foods ?? this.foods,
      totalKcal: totalKcal ?? this.totalKcal,
      lowerEstimateKcal: lowerEstimateKcal ?? this.lowerEstimateKcal,
      upperEstimateKcal: upperEstimateKcal ?? this.upperEstimateKcal,
      notes: notes ?? this.notes,
    );
  }

  factory Meal.fromMap(
    Map<String, dynamic> map, {
    required List<FoodItem> foods,
  }) {
    return Meal(
      id: map['id'] as int,
      dateTime: DateTime.parse(map['date_time'] as String),
      mealType: map['meal_type'] as String,
      imagePath: map['image_path'] as String?,
      foods: foods,
      totalKcal: (map['total_kcal'] as num).toDouble(),
      lowerEstimateKcal: (map['lower_estimate_kcal'] as num).toDouble(),
      upperEstimateKcal: (map['upper_estimate_kcal'] as num).toDouble(),
      notes: map['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toDatabaseMap() {
    return <String, dynamic>{
      'id': id,
      'date_time': dateTime.toIso8601String(),
      'meal_type': mealType,
      'image_path': imagePath,
      'total_kcal': totalKcal,
      'lower_estimate_kcal': lowerEstimateKcal,
      'upper_estimate_kcal': upperEstimateKcal,
      'notes': notes,
    };
  }
}
