import 'dart:convert';

import 'package:http/http.dart' as http;

/// Resolves the Lipa City barangay list for the report form's barangay
/// dropdown. The pilot only accepts reports for Lipa City (enforced
/// server-side in `ReporterReportStoreRequest`), so this walks the public
/// PSGC endpoints once (region -> province -> municipality -> barangays)
/// and caches the municipality code for the rest of the app session,
/// mirroring what the web form's `psgcCache` does.
class LocationCatalogService {
  LocationCatalogService._();

  static String? _lipaMunicipalityCode;
  static List<String>? _lipaBarangaysCache;

  static Future<List<String>> loadLipaBarangays(String baseUrl) async {
    final cached = _lipaBarangaysCache;
    if (cached != null) return cached;

    final municipalityCode = await _resolveLipaMunicipalityCode(baseUrl);
    final barangaysJson = await _getJson(baseUrl, '/api/psgc/barangays/$municipalityCode');
    final barangays = (barangaysJson['barangays'] as List<dynamic>? ?? const [])
        .map((item) => (item as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    _lipaBarangaysCache = barangays;
    return barangays;
  }

  static Future<String> _resolveLipaMunicipalityCode(String baseUrl) async {
    final cached = _lipaMunicipalityCode;
    if (cached != null) return cached;

    final regionsJson = await _getJson(baseUrl, '/api/psgc/regions');
    final regionCode = _findCode(regionsJson['regions'], 'CALABARZON');

    final provincesJson = await _getJson(baseUrl, '/api/psgc/provinces/$regionCode');
    final provinceCode = _findCode(provincesJson['provinces'], 'Batangas');

    final municipalitiesJson = await _getJson(baseUrl, '/api/psgc/municipalities/$provinceCode');
    // PSGC stores this as "City of Lipa", not "Lipa City" - match on "lipa"
    // alone since the ordering isn't consistent across PSGC entries.
    final municipalityCode = _findCode(municipalitiesJson['municipalities'], 'Lipa');

    _lipaMunicipalityCode = municipalityCode;
    return municipalityCode;
  }

  static String _findCode(dynamic items, String nameContains) {
    final list = (items as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final match = list.firstWhere(
      (item) => (item['name']?.toString() ?? '').toLowerCase().contains(nameContains.toLowerCase()),
      orElse: () => const {},
    );
    final code = match['psgc_code']?.toString();
    if (code == null || code.isEmpty) {
      throw Exception('Could not resolve PSGC code for "$nameContains".');
    }
    return code;
  }

  static Future<Map<String, dynamic>> _getJson(String baseUrl, String path) async {
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: const {'Accept': 'application/json'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load $path: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
