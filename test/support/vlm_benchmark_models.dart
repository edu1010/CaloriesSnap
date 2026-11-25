import 'package:calorie_snap/services/food_detection/vlm/vlm_model_catalog.dart';

/// The app's catalog plus models available only to the benchmarks.
const benchmarkModels = <String, VlmModelSpec>{
  'light': VlmModelCatalog.light,
  'precise': VlmModelCatalog.precise,
  'lfm3': VlmModelCatalog.lfm3,
  'lfm450': VlmModelSpec(
    id: 'lfm2.5-vl-450m-q4',
    name: 'LFM2.5-VL-450M',
    minDeviceRamGb: 4,
    imageMaxEdge: 512,
    model: VlmRemoteFile(
      fileName: 'LFM2.5-VL-450M-Q4_K_M.gguf',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-VL-450M-GGUF/resolve/'
          '1abed04b6fe71314d8c446a1371c03d7c332266d/LFM2.5-VL-450M-Q4_K_M.gguf',
      bytes: 229313568,
      sha256:
          '1093f1331319199bbcacdbd7ecc9aa6e5678db6b55073948d0f508be90c8ab68',
    ),
    projector: VlmRemoteFile(
      fileName: 'mmproj-LFM2.5-VL-450m-F16.gguf',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-VL-450M-GGUF/resolve/'
          '1abed04b6fe71314d8c446a1371c03d7c332266d/mmproj-LFM2.5-VL-450m-F16.gguf',
      bytes: 189126080,
      sha256:
          '51b458cfdbc736982145a35f798ce37611af0aab639e58b33473ba0c7815fd99',
    ),
  ),
  'minicpm': VlmModelSpec(
    id: 'minicpm-v-4.7-1b-q4',
    name: 'MiniCPM-V 4.7 1B',
    minDeviceRamGb: 8,
    imageMaxEdge: 512,
    model: VlmRemoteFile(
      fileName: 'MiniCPM-V-4_7-1B-Q4_K_M.gguf',
      url:
          'https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf/resolve/'
          'e81247fa2eac0d99e43aeac55da199221959af15/MiniCPM-V-4_7-1B-Q4_K_M.gguf',
      bytes: 672003680,
      sha256:
          'f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d',
    ),
    projector: VlmRemoteFile(
      fileName: 'mmproj-model-f16-4x.gguf',
      url:
          'https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf/resolve/'
          'e81247fa2eac0d99e43aeac55da199221959af15/mmproj-model-f16-4x.gguf',
      bytes: 901033888,
      sha256:
          '1e0ab439877e6896ded59ff24cdd242fdffb236394f6fc4a5b019cbd60bb5f4a',
    ),
  ),
};
