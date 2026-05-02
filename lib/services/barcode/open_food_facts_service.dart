import 'dart:convert';
import 'dart:io';

class BarcodeProduct {
  const BarcodeProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    required this.kcalPer100g,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String? imageUrl;
  final double kcalPer100g;
}

class OpenFoodFactsService {
  OpenFoodFactsService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const String _baseUrl = 'https://world.openfoodfacts.org';
  static const String _userAgent =
      'CalorieSnap/0.0.1-pre-alpha (contact: local-app)';
  static const Duration _requestTimeout = Duration(seconds: 10);

  final HttpClient _httpClient;

  Future<BarcodeProduct?> lookupByBarcode(String barcode) async {
    final normalized = _normalizeBarcode(barcode);
    if (normalized == null) {
      return null;
    }

    final uri = Uri.parse(
      '$_baseUrl/api/v2/product/$normalized.json'
      '?fields=code,product_name,product_name_es,generic_name,brands,image_url,nutriments',
    );

    try {
      final request = await _httpClient.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final status = decoded['status'];
      if (status is! num || status.toInt() != 1) {
        return null;
      }

      final product = decoded['product'];
      if (product is! Map<String, dynamic>) {
        return null;
      }

      final name =
          _asNullableString(product['product_name']) ??
          _asNullableString(product['product_name_es']) ??
          _asNullableString(product['generic_name']) ??
          'Unknown product';
      final brand = _asNullableString(product['brands']);
      final imageUrl = _asNullableString(product['image_url']);

      final nutriments = product['nutriments'];
      final kcal = _extractKcalPer100g(nutriments);
      if (kcal == null || kcal <= 0) {
        return null;
      }

      return BarcodeProduct(
        barcode: normalized,
        name: name,
        brand: brand,
        imageUrl: imageUrl,
        kcalPer100g: kcal,
      );
    } catch (_) {
      return null;
    }
  }

  double? _extractKcalPer100g(Object? nutrimentsObject) {
    if (nutrimentsObject is! Map<String, dynamic>) {
      return null;
    }

    final fromKcal =
        _asDouble(nutrimentsObject['energy-kcal_100g']) ??
        _asDouble(nutrimentsObject['energy_kcal_100g']) ??
        _asDouble(nutrimentsObject['energy-kcal']);
    if (fromKcal != null && fromKcal > 0) {
      return fromKcal;
    }

    final fromKj =
        _asDouble(nutrimentsObject['energy-kj_100g']) ??
        _asDouble(nutrimentsObject['energy_100g']) ??
        _asDouble(nutrimentsObject['energy-kj']) ??
        _asDouble(nutrimentsObject['energy']);
    if (fromKj == null || fromKj <= 0) {
      return null;
    }

    return fromKj / 4.184;
  }

  String? _normalizeBarcode(String barcode) {
    final digitsOnly = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 8 || digitsOnly.length > 14) {
      return null;
    }
    return digitsOnly;
  }

  String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final asString = value.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }
}
