/// One file of a downloadable model, pinned to an exact revision and hash.
class VlmRemoteFile {
  const VlmRemoteFile({
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  final String fileName;
  final String url;
  final int bytes;
  final String sha256;
}

/// A vision-language model the app can download and run on the device.
class VlmModelSpec {
  const VlmModelSpec({
    required this.id,
    required this.name,
    required this.model,
    required this.projector,
    required this.minDeviceRamGb,
    required this.imageMaxEdge,
  });

  final String id;
  final String name;
  final VlmRemoteFile model;
  final VlmRemoteFile projector;

  /// Total device memory below which loading is likely to be killed.
  final int minDeviceRamGb;

  /// Photos are downscaled to this edge before inference. It bounds the
  /// number of image tokens, which dominates latency on a phone.
  final int imageMaxEdge;

  int get totalBytes => model.bytes + projector.bytes;
  List<VlmRemoteFile> get files => <VlmRemoteFile>[model, projector];
}

/// Qwen3.5 small models (Apache-2.0), GGUF conversions by Unsloth.
class VlmModelCatalog {
  const VlmModelCatalog._();

  static const String _lightRevision =
      '6ab461498e2023f6e3c1baea90a8f0fe38ab64d0';
  static const String _preciseRevision =
      'f6d5376be1edb4d416d56da11e5397a961aca8ae';

  static const VlmModelSpec light = VlmModelSpec(
    id: 'qwen3.5-0.8b-q4',
    name: 'Qwen3.5 0.8B',
    minDeviceRamGb: 4,
    imageMaxEdge: 512,
    model: VlmRemoteFile(
      fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
      url:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/'
          '$_lightRevision/Qwen3.5-0.8B-Q4_K_M.gguf',
      bytes: 532517120,
      sha256:
          'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517',
    ),
    projector: VlmRemoteFile(
      fileName: 'mmproj-F16.gguf',
      url:
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/'
          '$_lightRevision/mmproj-F16.gguf',
      bytes: 204987232,
      sha256:
          '56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453',
    ),
  );

  static const VlmModelSpec precise = VlmModelSpec(
    id: 'qwen3.5-2b-q4',
    name: 'Qwen3.5 2B',
    minDeviceRamGb: 8,
    imageMaxEdge: 512,
    model: VlmRemoteFile(
      fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
      url:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/'
          '$_preciseRevision/Qwen3.5-2B-Q4_K_M.gguf',
      bytes: 1280835840,
      sha256:
          'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223',
    ),
    projector: VlmRemoteFile(
      fileName: 'mmproj-F16.gguf',
      url:
          'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/'
          '$_preciseRevision/mmproj-F16.gguf',
      bytes: 668227264,
      sha256:
          '7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7',
    ),
  );

  static const List<VlmModelSpec> all = <VlmModelSpec>[light, precise];
}
