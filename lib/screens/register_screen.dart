import 'package:flutter/material.dart';

import '../data/app_config.dart';
import '../data/auth_service.dart';
import '../data/location_catalog_service.dart';
import 'auth_components.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onRegistered, this.onBackToLogin, this.psgc});

  final ValueChanged<UserSession> onRegistered;
  final VoidCallback? onBackToLogin;

  /// Source of the address lists. Defaults to the public PSGC endpoints the
  /// website's forms use.
  final PsgcDirectory? psgc;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

/// One step of the address picker: its options, the chosen code, and its
/// loading/error state.
class _AddressLevel {
  List<PsgcPlace> items = const [];
  String? value;
  bool loading = false;
  String? error;

  // Bumped on every reload so a slow, superseded response is ignored.
  int generation = 0;

  void clear() {
    items = const [];
    value = null;
    loading = false;
    error = null;
    generation++;
  }

  String labelFor(String code) =>
      items.firstWhere((place) => place.code == code, orElse: () => PsgcPlace(code, code)).name;
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _houseNoController = TextEditingController();
  final _purokController = TextEditingController();
  final _landmarkController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  // Home address: any Philippine barangay, picked Region > Province >
  // City/Municipality > Barangay and sent as PSGC codes (names repeat across
  // the country). Incident reports keep their own Lipa City rule.
  late final PsgcDirectory _psgc = widget.psgc ?? ApiPsgcDirectory(AppConfig.apiBaseUrl);
  final _region = _AddressLevel();
  final _province = _AddressLevel();
  final _city = _AddressLevel();
  final _barangay = _AddressLevel();

  /// Province choice for cities directly under a region (all of NCR, and a
  /// few cities elsewhere); submitted as an empty province code.
  static const _noProvince = '__no_province__';
  static const _loadFailed = "Couldn't load this list. Check your connection and try again.";

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _load(
    _AddressLevel level,
    Future<List<PsgcPlace>> Function() fetch, {
    required String emptyMessage,
  }) async {
    final generation = ++level.generation;
    setState(() {
      level.loading = true;
      level.error = null;
    });
    try {
      final items = await fetch();
      if (!mounted || generation != level.generation) return;
      setState(() {
        level.items = items;
        level.loading = false;
        level.error = items.isEmpty ? emptyMessage : null;
      });
    } catch (_) {
      if (!mounted || generation != level.generation) return;
      setState(() {
        level.loading = false;
        level.error = _loadFailed;
      });
    }
  }

  Future<void> _loadRegions() =>
      _load(_region, _psgc.regions, emptyMessage: 'No regions are available right now. Please try again.');

  Future<void> _loadProvinces(String regionCode) async {
    await _load(_province, () async {
      final results = await Future.wait([_psgc.provinces(regionCode), _psgc.municipalities(regionCode)]);
      return [
        ...results[0],
        if (results[1].isNotEmpty) const PsgcPlace(_noProvince, 'No province (city directly under the region)'),
      ];
    }, emptyMessage: 'No locations are available for this region yet.');

    // A region whose cities all sit directly under it (NCR) has one choice.
    if (mounted && _province.items.length == 1 && _province.value == null) {
      _selectProvince(_province.items.single.code);
    }
  }

  Future<void> _loadCities(String parentCode) => _load(
    _city,
    () => _psgc.municipalities(parentCode),
    emptyMessage: 'No cities or municipalities are available here yet.',
  );

  Future<void> _loadBarangays(String cityCode) =>
      _load(_barangay, () => _psgc.barangays(cityCode), emptyMessage: 'No barangays are available for this city yet.');

  String _cityParentCode() => _province.value == _noProvince ? _region.value! : _province.value!;

  void _selectRegion(String? code) {
    if (code == null || code == _region.value) return;
    setState(() {
      _region.value = code;
      _province.clear();
      _city.clear();
      _barangay.clear();
    });
    _loadProvinces(code);
  }

  void _selectProvince(String? code) {
    if (code == null || code == _province.value) return;
    setState(() {
      _province.value = code;
      _city.clear();
      _barangay.clear();
    });
    _loadCities(_cityParentCode());
  }

  void _selectCity(String? code) {
    if (code == null || code == _city.value) return;
    setState(() {
      _city.value = code;
      _barangay.clear();
    });
    _loadBarangays(code);
  }

  void _retry(_AddressLevel level) {
    if (level == _region) {
      _loadRegions();
    } else if (level == _province && _region.value != null) {
      _loadProvinces(_region.value!);
    } else if (level == _city && _province.value != null) {
      _loadCities(_cityParentCode());
    } else if (level == _barangay && _city.value != null) {
      _loadBarangays(_city.value!);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _houseNoController.dispose();
    _purokController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length == 11 &&
      _passwordController.text.length >= 8 &&
      _houseNoController.text.trim().isNotEmpty &&
      _purokController.text.trim().isNotEmpty &&
      _region.value != null &&
      _province.value != null &&
      _city.value != null &&
      _barangay.value != null;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final session = await AuthService.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        houseNo: _houseNoController.text.trim(),
        purok: _purokController.text.trim(),
        regionCode: _region.value!,
        provinceCode: _province.value == _noProvince ? '' : _province.value!,
        cityCode: _city.value!,
        barangayCode: _barangay.value!,
        barangay: _barangay.labelFor(_barangay.value!),
        landmark: _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
      );
      if (!mounted) return;
      widget.onRegistered(session);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _addressField({
    required _AddressLevel level,
    required String label,
    required String glyph,
    required String hint,
    required String waitingHint,
    required bool parentChosen,
    required String loadingText,
    required ValueChanged<String?> onChanged,
    required String name,
    String? helper,
  }) {
    return AuthDropdownField(
      // Rebuilt whenever the choice changes (including automatic ones), since
      // the dropdown only reads its initial value when it is created.
      key: ValueKey('address-$name-${level.value}'),
      label: label,
      glyph: glyph,
      hint: parentChosen ? hint : waitingHint,
      items: level.items.map((place) => place.code).toList(),
      itemLabel: level.labelFor,
      value: level.value,
      onChanged: onChanged,
      enabled: parentChosen,
      loading: level.loading,
      loadingText: loadingText,
      error: level.error,
      onRetry: () => _retry(level),
      helper: helper,
    );
  }

  @override
  Widget build(BuildContext context) {
    void refresh(String _) => setState(() {});

    // Same fields, order, labels and placeholders as the website's register
    // form (resources/views/reporter/register.blade.php).
    return AuthPage(
      tagline: 'Community-first hazard preparedness system',
      title: 'Create Account',
      subtitle: 'Set up your Rapid Alert access profile',
      children: [
        if (_error != null) AuthErrorBanner(message: _error!),
        AuthField(label: 'First Name', glyph: 'U', hint: 'Enter first name', controller: _firstNameController, onChanged: refresh),
        AuthField(label: 'Last Name', glyph: 'U', hint: 'Enter last name', controller: _lastNameController, onChanged: refresh),
        AuthField(
          label: 'Email',
          glyph: '@',
          hint: 'Enter email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onChanged: refresh,
        ),
        AuthField(
          label: 'Phone Number',
          glyph: '#',
          hint: '09XXXXXXXXX',
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          onChanged: refresh,
        ),
        AuthField(label: 'House No.', glyph: 'H', hint: 'House number', controller: _houseNoController, onChanged: refresh),
        AuthField(label: 'Purok', glyph: 'P', hint: 'Purok', controller: _purokController, onChanged: refresh),
        _addressField(
          name: 'region',
          level: _region,
          label: 'Region',
          glyph: 'R',
          hint: 'Select region',
          waitingHint: 'Select region',
          parentChosen: true,
          loadingText: 'Loading regions…',
          onChanged: _selectRegion,
        ),
        _addressField(
          name: 'province',
          level: _province,
          label: 'Province',
          glyph: 'P',
          hint: 'Select province',
          waitingHint: 'Select a region first',
          parentChosen: _region.value != null,
          loadingText: 'Loading provinces…',
          onChanged: _selectProvince,
        ),
        _addressField(
          name: 'city',
          level: _city,
          label: 'City / Municipality',
          glyph: 'C',
          hint: 'Select city / municipality',
          waitingHint: 'Select a province first',
          parentChosen: _province.value != null,
          loadingText: 'Loading cities and municipalities…',
          onChanged: _selectCity,
        ),
        _addressField(
          name: 'barangay',
          level: _barangay,
          label: 'Barangay',
          glyph: 'B',
          hint: 'Select barangay',
          waitingHint: 'Select a city / municipality first',
          parentChosen: _city.value != null,
          loadingText: 'Loading barangays…',
          onChanged: (code) => setState(() => _barangay.value = code),
          helper: 'Your home address. Emergency reports are currently accepted for incidents in Lipa City.',
        ),
        AuthField(
          label: 'Landmark (Optional)',
          glyph: 'L',
          hint: 'Nearby landmark',
          controller: _landmarkController,
          onChanged: refresh,
        ),
        AuthField(
          label: 'Password',
          glyph: 'L',
          hint: 'Create password',
          helper: 'At least 8 characters.',
          controller: _passwordController,
          obscureText: _obscurePassword,
          onChanged: refresh,
          suffixIcon: PasswordVisibilityToggle(
            obscured: _obscurePassword,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        AuthPrimaryButton(
          label: 'Create Account',
          busy: _submitting,
          onPressed: _canSubmit ? _submit : null,
        ),
        if (widget.onBackToLogin != null)
          AuthFooter(
            children: [
              AuthFooterLink(lead: 'Already have an account?', label: 'Login Here', onTap: widget.onBackToLogin!),
            ],
          ),
      ],
    );
  }
}
