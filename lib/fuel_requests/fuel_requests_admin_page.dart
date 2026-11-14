import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'fuel_customer_document_review.dart';
import 'fuel_requests_management_tabs.dart';

class FuelRequestsAdminPage extends StatefulWidget {
  const FuelRequestsAdminPage({super.key});

  @override
  State<FuelRequestsAdminPage> createState() => _FuelRequestsAdminPageState();
}

class _FuelRequestsAdminPageState extends State<FuelRequestsAdminPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  int _section = 0; // 0 Stations, 1 Customers, 2 OMCs, 3 Regional Approvers
  final _omcKey = GlobalKey<FuelOmcsAdminTabState>();
  final _regionalKey = GlobalKey<FuelRegionalApproversTabState>();
  final _stationKey = GlobalKey<_FuelStationExtrasAdminState>();
  bool _loading = true;
  bool _authorized = false;
  String? _error;
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed = await _supabase.rpc(
        'has_fuel_request_permission',
        params: {'p_permission': 'APPLICANT_ADMIN'},
      );
      if (allowed != true) {
        throw Exception('Fuel Requests Administrator permission required.');
      }
      final response = await _supabase.rpc('admin_get_fuel_customers');
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _customers = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _customers = [];
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(dynamic v) =>
      v == null || v.toString().trim().isEmpty ? '—' : v.toString();

  String _allowance(Map<String, dynamic> customer, String product) {
    final limit = customer['${product}_limit'];
    final type = customer['${product}_allowance_type']?.toString();
    if (limit == null || type == null) return 'Not enabled';
    final number = num.tryParse(limit.toString());
    final amount = number == null
        ? limit.toString()
        : number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(2);
    final period = switch (type) {
      'DAILY' => 'day',
      'WEEKLY' => 'week',
      'MONTHLY' => 'month',
      'PER_SESSION' => 'session',
      _ => type,
    };
    return '$amount L / $period';
  }

  Future<void> _showEditor([Map<String, dynamic>? customer]) async {
    if (!_authorized) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomerEditor(customer: customer),
    );
    if (changed == true) await _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    // The administration navigation stays visible in both sections.
    final term = _searchController.text.trim().toLowerCase();
    final filtered = _customers.where((c) {
      if (term.isEmpty) return true;
      return [
        c['applicant_name'],
        c['company_name'],
        c['email'],
        c['phone_number'],
        c['account_status'],
      ].any((v) => (v?.toString().toLowerCase() ?? '').contains(term));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Fuel Requests Administration',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              _sectionButton(
                'Filling Stations',
                Icons.local_gas_station_outlined,
                _section == 0,
                () => setState(() => _section = 0),
              ),
              _sectionButton(
                'Container Fuel Customers',
                Icons.people_outline,
                _section == 1,
                () => setState(() => _section = 1),
              ),
              _sectionButton(
                'OMCs',
                Icons.business_outlined,
                _section == 2,
                () => setState(() => _section = 2),
              ),
              _sectionButton(
                'Regional Approvers',
                Icons.admin_panel_settings_outlined,
                _section == 3,
                () => setState(() => _section = 3),
              ),
              OutlinedButton.icon(
                onPressed: switch (_section) {
                  0 => () => _stationKey.currentState?._load(),
                  1 => _loading ? null : _loadCustomers,
                  2 => () => _omcKey.currentState?.refresh(),
                  _ => () => _regionalKey.currentState?.refresh(),
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            0 => _FuelStationExtrasAdmin(key: _stationKey),
            1 => _customerContent(filtered),
            2 => FuelOmcsAdminTab(key: _omcKey),
            _ => FuelRegionalApproversTab(key: _regionalKey),
          },
        ),
      ],
    );
  }

  Widget _sectionButton(
    String label,
    IconData icon,
    bool selected,
    VoidCallback action,
  ) => selected
      ? FilledButton.icon(
          onPressed: action,
          icon: Icon(icon),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: action,
          icon: Icon(icon),
          label: Text(label),
        );

  Widget _customerContent(List<Map<String, dynamic>> filtered) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('Registered customers and fuel allowances'),
          const SizedBox(height: 18),
          if (_authorized)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 400,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search customers',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showEditor(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add Customer'),
                ),
              ],
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SelectableText(_error!, style: const TextStyle(color: Colors.red))
          else if (_authorized)
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matching customers found.'))
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Customer')),
                            DataColumn(label: Text('Actions')),
                            DataColumn(label: Text('Company')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Category')),
                            DataColumn(label: Text('Auto Approval')),
                            DataColumn(label: Text('Petrol')),
                            DataColumn(label: Text('Diesel')),
                            DataColumn(label: Text('Kerosene')),
                            DataColumn(label: Text('Expires')),
                          ],
                          rows: filtered
                              .map(
                                (c) => DataRow(
                                  cells: [
                                    DataCell(Text(_value(c['applicant_name']))),

                                    // Customer actions
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Edit customer',
                                            onPressed: () => _showEditor(c),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Verify Documents',
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FuelCustomerDocumentReview(
                                                        applicantId: c['id']
                                                            .toString(),
                                                        customerName:
                                                            c['applicant_name']
                                                                ?.toString() ??
                                                            'Customer',
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.fact_check_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    DataCell(Text(_value(c['company_name']))),
                                    DataCell(Text(_value(c['email']))),
                                    DataCell(Text(_value(c['account_status']))),
                                    DataCell(
                                      Text(
                                        c['allowance_category'] == 'TYPE_B'
                                            ? 'Type B'
                                            : 'Type A',
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        c['auto_approval_enabled'] == true
                                            ? 'Enabled'
                                            : 'Disabled',
                                      ),
                                    ),
                                    DataCell(Text(_allowance(c, 'petrol'))),
                                    DataCell(Text(_allowance(c, 'diesel'))),
                                    DataCell(Text(_allowance(c, 'kerosene'))),
                                    DataCell(Text(_value(c['expires_on']))),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _CustomerEditor extends StatefulWidget {
  const _CustomerEditor({this.customer});
  final Map<String, dynamic>? customer;

  @override
  State<_CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends State<_CustomerEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _registration;
  late DateTime _validFrom;
  late DateTime _expiresOn;
  late String _category;
  late String _status;
  late bool _autoApprove;
  bool _saving = false;
  String? _error;
  late final Map<String, _ProductLimit> _limits;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer ?? {};
    _name = TextEditingController(text: c['applicant_name']?.toString() ?? '');
    _company = TextEditingController(text: c['company_name']?.toString() ?? '');
    _email = TextEditingController(text: c['email']?.toString() ?? '');
    _phone = TextEditingController(text: c['phone_number']?.toString() ?? '');
    _registration = TextEditingController(
      text: c['registration_number']?.toString() ?? '',
    );
    _category = c['allowance_category'] == 'TYPE_B' ? 'TYPE_B' : 'TYPE_A';
    _status = c['account_status']?.toString() ?? 'ACTIVE';
    _autoApprove = c['auto_approval_enabled'] == true;
    final today = DateTime.now();
    _validFrom = DateTime.tryParse(c['valid_from']?.toString() ?? '') ?? today;
    _expiresOn =
        DateTime.tryParse(c['expires_on']?.toString() ?? '') ??
        DateTime(today.year + 1, today.month, today.day);
    _limits = {
      for (final product in ['PETROL', 'DIESEL', 'KEROSENE'])
        product: _ProductLimit(
          enabled: c['${product.toLowerCase()}_limit'] != null,
          amount: c['${product.toLowerCase()}_limit']?.toString() ?? '',
          period:
              c['${product.toLowerCase()}_allowance_type']?.toString() ??
              (_category == 'TYPE_B' ? 'PER_SESSION' : 'MONTHLY'),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in [_name, _company, _email, _phone, _registration]) {
      c.dispose();
    }
    for (final l in _limits.values) {
      l.controller.dispose();
    }
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool start) async {
    final current = start ? _validFrom : _expiresOn;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (start) {
        _validFrom = date;
      } else {
        _expiresOn = date;
      }
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return '$label is required';
        }
        if (label == 'Email' &&
            value != null &&
            value.trim().isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
          return 'Enter a valid email';
        }
        return null;
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_expiresOn.isBefore(_validFrom)) {
      setState(
        () => _error = 'Expiry date must be on or after the start date.',
      );
      return;
    }
    final allowances = <Map<String, dynamic>>[];
    for (final entry in _limits.entries) {
      if (!entry.value.enabled) continue;
      final amount = num.tryParse(entry.value.controller.text.trim());
      if (amount == null ||
          amount <= 0 ||
          amount > 999999999999.99 ||
          (amount * 100).roundToDouble() != amount * 100) {
        setState(
          () => _error =
              'Enter a valid positive limit (maximum 2 decimal places) for ${entry.key}.',
        );
        return;
      }
      allowances.add({
        'product': entry.key,
        'allowance_type': _category == 'TYPE_B'
            ? 'PER_SESSION'
            : entry.value.period,
        'limit_litres': amount,
        'active': true,
      });
    }

    // Intentionally do not write directly to fuel_applicants or Supabase Auth.
    // The backend must expose an APPLICANT_ADMIN-authorized operation that
    // atomically updates the applicant and allowances, and provisions Auth
    // users server-side for new accounts.
    final payload = {
      if (_editing) 'id': widget.customer!['id'],
      'applicant_name': _name.text.trim(),
      'company_name': _company.text.trim(),
      'email': _email.text.trim(),
      'phone_number': _phone.text.trim(),
      'registration_number': _registration.text.trim(),
      'account_status': _status,
      'auto_approval_enabled': _autoApprove,
      'valid_from': _date(_validFrom),
      'expires_on': _date(_expiresOn),
      'allowance_category': _category,
      'allowances': allowances,
    };

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Backend contract to implement next:
      // Edge Function 'admin-save-fuel-customer' accepts the above payload,
      // verifies APPLICANT_ADMIN server-side, and returns success.
      await Supabase.instance.client.functions
          .invoke('admin-save-fuel-customer', body: payload)
          .then((response) {
            if (response.status < 200 || response.status >= 300) {
              throw Exception(
                'Customer save failed (${response.status}): ${response.data}',
              );
            }
          });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            'Unable to save customer. The secure admin-save-fuel-customer '
            'backend must be deployed first. Details: $e',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit Customer' : 'Add Customer'),
      content: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Customer details',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _field(_name, 'Customer name', required: true),
                  const SizedBox(height: 12),
                  _field(_company, 'Company / Organization'),
                  const SizedBox(height: 12),
                  _field(
                    _email,
                    'Email',
                    required: true,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _phone,
                    'Phone number',
                    required: true,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _field(_registration, 'Registration / ID number'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Account status',
                      border: OutlineInputBorder(),
                    ),
                    items: {_status, 'ACTIVE', 'SUSPENDED'}
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(true),
                        icon: const Icon(Icons.event),
                        label: Text('Valid from: ${_date(_validFrom)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(false),
                        icon: const Icon(Icons.event),
                        label: Text('Expires: ${_date(_expiresOn)}'),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Fuel allowance category',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'TYPE_A',
                        child: Text('Type A — Daily / Weekly / Monthly'),
                      ),
                      DropdownMenuItem(
                        value: 'TYPE_B',
                        child: Text(
                          'Type B — Per session (unlimited sessions)',
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                        for (final limit in _limits.values) {
                          limit.period = value == 'TYPE_B'
                              ? 'PER_SESSION'
                              : 'MONTHLY';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable automatic approval'),
                    subtitle: const Text(
                      'Requests outside allowance limits require manual approval.',
                    ),
                    value: _autoApprove,
                    onChanged: (v) => setState(() => _autoApprove = v),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Independent product allowances',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final product in ['PETROL', 'DIESEL', 'KEROSENE'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _productRow(product),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Customer'),
        ),
      ],
    );
  }

  Widget _productRow(String product) {
    final limit = _limits[product]!;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(product),
              value: limit.enabled,
              onChanged: (v) => setState(() => limit.enabled = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (limit.enabled)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextFormField(
                      controller: limit.controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Limit (litres)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (!limit.enabled) return null;
                        final n = num.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) {
                          return 'Enter a positive limit';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      initialValue: _category == 'TYPE_B'
                          ? 'PER_SESSION'
                          : limit.period,
                      decoration: const InputDecoration(
                        labelText: 'Period',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          (_category == 'TYPE_B'
                                  ? ['PER_SESSION']
                                  : ['DAILY', 'WEEKLY', 'MONTHLY'])
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.replaceAll('_', ' ')),
                                ),
                              )
                              .toList(),
                      onChanged: _category == 'TYPE_B'
                          ? null
                          : (v) => setState(
                              () => limit.period = v ?? limit.period,
                            ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ProductLimit {
  _ProductLimit({
    required this.enabled,
    required String amount,
    required this.period,
  }) : controller = TextEditingController(text: amount);

  bool enabled;
  String period;
  final TextEditingController controller;
}

// Station owner email and minimum stock settings. Existing customer editor is unchanged.
class _FuelStationExtrasAdmin extends StatefulWidget {
  const _FuelStationExtrasAdmin({super.key});

  @override
  State<_FuelStationExtrasAdmin> createState() =>
      _FuelStationExtrasAdminState();
}

class _FuelStationExtrasAdminState extends State<_FuelStationExtrasAdmin> {
  final _db = Supabase.instance.client;
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stations = [];
  String? _districtFilter;
  String? _omcFilter;
  String? _statusFilter;
  String? _activeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Both RPCs require public.is_admin() on the server.
      final base = List<Map<String, dynamic>>.from(
        await _db.rpc('admin_list_filling_stations'),
      );
      final extras = List<Map<String, dynamic>>.from(
        await _db.rpc('admin_list_filling_station_extras'),
      );
      final byId = <String, Map<String, dynamic>>{
        for (final item in extras) item['station_id'].toString(): item,
      };
      for (final station in base) {
        final extra = byId[station['id'].toString()];
        if (extra != null) station.addAll(extra);
      }
      if (!mounted) return;
      setState(() => _stations = base);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _display(dynamic value) =>
      value == null || value.toString().trim().isEmpty ? '—' : value.toString();

  List<String> _choices(String key) =>
      _stations
          .map((s) => s[key]?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Future<void> _edit(Map<String, dynamic> station) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StationExtrasEditor(
        station: station,
        districts: _stations
            .where((s) => s['district_id'] != null)
            .map(
              (s) => MapEntry(
                s['district_id'].toString(),
                s['district_name']?.toString() ?? 'Unknown district',
              ),
            )
            .fold<Map<String, String>>({}, (map, entry) {
              map[entry.key] = entry.value;
              return map;
            }),
      ),
    );
    if (changed == true) await _load();
  }

  Map<String, String> get _districtsById => {
    for (final station in _stations)
      if (station['district_id'] != null)
        station['district_id'].toString():
            station['district_name']?.toString() ?? 'Unknown district',
  };

  Future<void> _add() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StationExtrasEditor(
        station: const {},
        districts: _districtsById,
        isNew: true,
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();

    final shown = _stations.where((s) {
      if (_districtFilter != null &&
          s['district_name']?.toString() != _districtFilter) {
        return false;
      }

      if (_omcFilter != null && s['omc']?.toString() != _omcFilter) {
        return false;
      }

      if (_statusFilter != null &&
          (_statusFilter == '__NULL__'
              ? s['operational_status'] != null
              : s['operational_status']?.toString() != _statusFilter)) {
        return false;
      }

      if (_activeFilter != null &&
          (s['active'] == true ? 'Active' : 'Inactive') != _activeFilter) {
        return false;
      }

      return query.isEmpty ||
          [
            s['name'],
            s['district_name'],
            s['omc'],
            s['owner_email'],
            s['licence_number'],
            s['location_description'],
          ].any((v) => (v?.toString().toLowerCase() ?? '').contains(query));
    }).toList();
    final districts = _choices('district_name');
    final omcs = _choices('omc');
    final statuses = _choices('operational_status');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Filling Stations',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Add Filling Station'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage station details, OMC assignment, contacts and stock bottom edges.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search stations',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              _filter(
                'District',
                _districtFilter,
                districts
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                (v) => setState(() => _districtFilter = v),
              ),
              _filter(
                'OMC',
                _omcFilter,
                omcs
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                (v) => setState(() => _omcFilter = v),
              ),
              _filter(
                'Operational status',
                _statusFilter,
                [
                  ...statuses.map(
                    (v) => DropdownMenuItem(value: v, child: Text(v)),
                  ),
                  const DropdownMenuItem(
                    value: '__NULL__',
                    child: Text('Not specified'),
                  ),
                ],
                (v) => setState(() => _statusFilter = v),
              ),
              _filter(
                'Active status',
                _activeFilter,
                const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                ],
                (v) => setState(() => _activeFilter = v),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _search.clear();
                  _districtFilter = null;
                  _omcFilter = null;
                  _statusFilter = null;
                  _activeFilter = null;
                }),
                child: const Text('Clear filters'),
              ),
              Text('${shown.length} of ${_stations.length} stations'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: SelectableText(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          else
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No matching stations found.'))
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Station')),
                            DataColumn(label: Text('Edit')),
                            DataColumn(label: Text('District')),
                            DataColumn(label: Text('OMC')),
                            DataColumn(label: Text('Operational status')),
                            DataColumn(label: Text('Active')),
                            DataColumn(label: Text('Location')),
                            DataColumn(label: Text('Licence')),
                            DataColumn(label: Text('Owner email')),
                            DataColumn(label: Text('Petrol bottom edge (L)')),
                            DataColumn(label: Text('Diesel bottom edge (L)')),
                          ],
                          rows: shown
                              .map(
                                (s) => DataRow(
                                  cells: [
                                    DataCell(Text(_display(s['name']))),
                                    DataCell(
                                      IconButton(
                                        tooltip: 'Edit all station details',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _edit(s),
                                      ),
                                    ),
                                    DataCell(
                                      Text(_display(s['district_name'])),
                                    ),
                                    DataCell(Text(_display(s['omc']))),
                                    DataCell(
                                      Text(_display(s['operational_status'])),
                                    ),
                                    DataCell(
                                      Text(
                                        s['active'] == true
                                            ? 'Active'
                                            : 'Inactive',
                                      ),
                                    ),
                                    DataCell(
                                      Text(_display(s['location_description'])),
                                    ),
                                    DataCell(
                                      Text(_display(s['licence_number'])),
                                    ),
                                    DataCell(Text(_display(s['owner_email']))),
                                    DataCell(
                                      Text(
                                        _display(
                                          s['petrol_bottom_edge_litres'],
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _display(
                                          s['diesel_bottom_edge_litres'],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _filter(
    String label,
    String? value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String?> changed,
  ) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('All')),
          ...items,
        ],
        onChanged: changed,
      ),
    );
  }
}

class _StationExtrasEditor extends StatefulWidget {
  const _StationExtrasEditor({
    required this.station,
    required this.districts,
    this.isNew = false,
  });
  final Map<String, dynamic> station;
  final Map<String, String> districts;
  final bool isNew;

  @override
  State<_StationExtrasEditor> createState() => _StationExtrasEditorState();
}

class _StationExtrasEditorState extends State<_StationExtrasEditor> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  String? _districtId;
  String? _status;
  bool _active = true;
  bool _saving = false;
  String? _error;
  String? _createdStationId;

  static const _statuses = [
    'Operational',
    'Under construction',
    'Approved to Construct',
    'Not Operational',
  ];

  TextEditingController _field(String key) => _fields[key]!;

  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'omc',
      'location_description',
      'licence_number',
      'latitude',
      'longitude',
      'dealer_contact_details',
      'owner_email',
      'petrol_bottom_edge_litres',
      'diesel_bottom_edge_litres',
    ]) {
      _fields[key] = TextEditingController(
        text: widget.station[key]?.toString() ?? '',
      );
    }
    _districtId = widget.station['district_id']?.toString();
    _status = widget.station['operational_status']?.toString();
    _active = widget.isNew || widget.station['active'] == true;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? input) =>
      (input ?? '').trim().isEmpty ? 'Required' : null;
  String? _litres(String? input) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    return n == null || !n.isFinite || n < 0
        ? 'Enter a non-negative number'
        : null;
  }

  String? _latitudeValidator(String? input) => _coordinate(input, -90, 90);
  String? _longitudeValidator(String? input) => _coordinate(input, -180, 180);
  String? _coordinate(String? input, double min, double max) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return null;
    final n = double.tryParse(s);
    return n == null || !n.isFinite || n < min || n > max
        ? 'Enter a number between $min and $max'
        : null;
  }

  String? _emailValidator(String? input) {
    final s = (input ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)
        ? null
        : 'Enter a valid email address';
  }

  String? _nullable(String key) {
    final s = _field(key).text.trim();
    return s.isEmpty ? null : s;
  }

  double? _double(String key) {
    final s = _nullable(key);
    return s == null ? null : double.parse(s);
  }

  num? _number(String key) {
    final s = _nullable(key);
    return s == null ? null : num.parse(s);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_districtId == null) {
      setState(() => _error = 'Select a district');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var baseSaved = false;
    try {
      final db = Supabase.instance.client;
      final stationId = widget.isNew && _createdStationId == null
          ? await db.rpc(
              'admin_add_filling_station',
              params: {
                'p_name': _field('name').text.trim(),
                'p_district_id': _districtId,
                'p_location_description': _nullable('location_description'),
                'p_licence_number': _nullable('licence_number'),
                'p_operational_status': _status,
                'p_omc': _nullable('omc'),
                'p_latitude': _double('latitude'),
                'p_longitude': _double('longitude'),
                'p_dealer_contact_details': _nullable('dealer_contact_details'),
                'p_active': _active,
              },
            )
          : (_createdStationId ?? widget.station['id']);
      if (widget.isNew && _createdStationId == null) {
        _createdStationId = stationId.toString();
      }
      if (!widget.isNew) {
        await db.rpc(
          'admin_update_filling_station',
          params: {
            'p_station_id': widget.station['id'],
            'p_name': _field('name').text.trim(),
            'p_district_id': _districtId,
            'p_location_description': _nullable('location_description'),
            'p_licence_number': _nullable('licence_number'),
            'p_operational_status': _status,
            'p_omc': _nullable('omc'),
            'p_latitude': _double('latitude'),
            'p_longitude': _double('longitude'),
            'p_dealer_contact_details': _nullable('dealer_contact_details'),
            'p_active': _active,
          },
        );
      }
      baseSaved = true;
      await db.rpc(
        'admin_update_filling_station_extra',
        params: {
          'p_station_id': stationId,
          'p_owner_email': _nullable('owner_email'),
          'p_petrol_bottom_edge_litres': _number('petrol_bottom_edge_litres'),
          'p_diesel_bottom_edge_litres': _number('diesel_bottom_edge_litres'),
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = baseSaved
              ? 'Station core details were saved, but owner/bottom-edge details failed: $e. Retry Save to complete without creating another station.'
              : 'Unable to save station: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(
    String key,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int maxLines = 1,
  }) => TextFormField(
    controller: _field(key),
    keyboardType: keyboard,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    final districtItems = widget.districts.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
      title: Text(
        widget.isNew
            ? 'Add filling station'
            : 'Edit filling station: ${widget.station['name']}',
      ),
      content: SizedBox(
        width: 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input('name', 'Filling station name', validator: _required),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _districtId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'District',
                    border: OutlineInputBorder(),
                  ),
                  items: districtItems
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _districtId = v),
                  validator: (v) => v == null ? 'Select a district' : null,
                ),
                const SizedBox(height: 12),
                _input('omc', 'OMC (company name)'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Operational status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Not specified'),
                    ),
                    ..._statuses.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active station'),
                  value: _active,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _active = v),
                ),
                const SizedBox(height: 12),
                _input(
                  'location_description',
                  'Physical location',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _input('licence_number', 'Licence number'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _input(
                        'latitude',
                        'Latitude',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: _latitudeValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _input(
                        'longitude',
                        'Longitude',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        validator: _longitudeValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _input(
                  'dealer_contact_details',
                  'Dealer contact details',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _input(
                  'owner_email',
                  'Station owner email',
                  keyboard: TextInputType.emailAddress,
                  validator: _emailValidator,
                ),
                const SizedBox(height: 12),
                _input(
                  'petrol_bottom_edge_litres',
                  'Petrol bottom edge (litres)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _litres,
                ),
                const SizedBox(height: 12),
                _input(
                  'diesel_bottom_edge_litres',
                  'Diesel bottom edge (litres)',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _litres,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
