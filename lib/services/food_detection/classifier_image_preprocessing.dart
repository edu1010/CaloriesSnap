import 'package:image/image.dart' as img;

/// Mirrors the training pipeline: RGB intensities from the entire photograph
/// are resized to the model input. Orientation is applied before resizing.
img.Image prepareClassifierImage(img.Image image, int width, int height) {
  return img.copyResize(
    img
        .bakeOrientation(image)
        .convert(format: img.Format.uint8, numChannels: 3),
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );
}
