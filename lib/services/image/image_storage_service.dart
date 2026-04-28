import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  Future<String> copyToAppStorage(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('Image file not found at $sourcePath');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'meal_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath).toLowerCase();
    final fileName = 'meal_${DateTime.now().millisecondsSinceEpoch}$extension';
    final targetPath = p.join(imagesDir.path, fileName);

    final copied = await sourceFile.copy(targetPath);
    return copied.path;
  }
}
