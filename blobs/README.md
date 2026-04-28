Place the TensorFlow Lite C library for Windows in this folder:

- `libtensorflowlite_c-win.dll`

This file is required by `tflite_flutter` for Windows desktop inference.

Build/download reference:

- Bazel guide: https://www.tensorflow.org/lite/guide/build_cmake#build_tensorflow_lite_with_bazel
- CMake guide: https://www.tensorflow.org/lite/guide/build_cmake

After placing the DLL, `flutter build windows` will copy it into the app bundle.
