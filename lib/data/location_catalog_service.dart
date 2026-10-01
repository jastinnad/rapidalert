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

/// One PSGC place: a region, province, city/municipality or barangay.
class PsgcPlace {
  const PsgcPlace(this.code, this.name);

  final String code;
  final String name;
}

/// The PSGC lookups behind the registration address picker
/// (Region -> Province -> City/Municipality -> Barangay), identified by code
/// because barangay names repeat across the country.
abstract class PsgcDirectory {
  Future<List<PsgcPlace>> regions();

  Future<List<PsgcPlace>> provinces(String regionCode);

  /// Cities/municipalities under a province, or directly under a region
  /// (all of NCR, and a few cities elsewhere).
  Future<List<PsgcPlace>> municipalities(String parentCode);

  Future<List<PsgcPlace>> barangays(String cityCode);
}

/// [PsgcDirectory] over the public `/api/psgc/*` endpoints the web forms use.
class ApiPsgcDirectory implements PsgcDirectory {
  ApiPsgcDirectory(this.baseUrl);

  final String baseUrl;

  static const _timeout = Duration(seconds: 20);

  // Per URL for the app session; an empty result is never cached.
  static final Map<String, List<PsgcPlace>> _cache = {};

  @override
  Future<List<PsgcPlace>> regions() => _places('/api/psgc/regions', 'regions');

  @override
  Future<List<PsgcPlace>> provinces(String regionCode) =>
      _places('/api/psgc/provinces/${Uri.encodeComponent(regionCode)}', 'provinces');

  @override
  Future<List<PsgcPlace>> municipalities(String parentCode) =>
      _places('/api/psgc/municipalities/${Uri.encodeComponent(parentCode)}', 'municipalities');

  @override
  Future<List<PsgcPlace>> barangays(String cityCode) =>
      _places('/api/psgc/barangays/${Uri.encodeComponent(cityCode)}', 'barangays');

  Future<List<PsgcPlace>> _places(String path, String key) async {
    final url = '$baseUrl$path';
    final cached = _cache[url];
    if (cached != null) return cached;

    final response = await http.get(Uri.parse(url), headers: const {'Accept': 'application/json'}).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load $path (HTTP ${response.statusCode})');
    }
    final places = ((jsonDecode(response.body) as Map<String, dynamic>)[key] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((item) => PsgcPlace(item['psgc_code']?.toString() ?? '', item['name']?.toString() ?? ''))
        .where((place) => place.code.isNotEmpty && place.name.isNotEmpty)
        .toList();

    if (places.isNotEmpty) _cache[url] = places;
    return places;
  }
}
