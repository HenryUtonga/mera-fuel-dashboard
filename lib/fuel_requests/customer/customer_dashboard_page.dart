import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/mera_theme.dart';
import '../services/fuel_request_location_service.dart';
import 'customer_documents_tab.dart';

class CustomerDashboardPage extends StatefulWidget {
  const CustomerDashboardPage({super.key});

  @override
  State<CustomerDashboardPage> createState() => _CustomerDashboardPageState();
}

class _CustomerDashboardPageState extends State<CustomerDashboardPage> {
  final _supabase = Supabase.instance.client;
  final _locationService = FuelRequestLocationService();
  final _formKey = GlobalKey<FormState>();

  final _reasonController = TextEditingController();
  final _petrolController = TextEditingController();
  final _dieselController = TextEditingController();

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _allowances = [];

  List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> _omcs = [];
  List<Map<String, dynamic>> _stations = [];

  String? _districtId;
  String? _omcId;
  String? _stationId;
  String? _error;

  bool _loading = true;
  bool _loadingLocations = false;
  bool _submitting = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadDistricts();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _petrolController.dispose();
    _dieselController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    debugPrint('CUSTOMER AUTH USER: ${user?.id}');
    debugPrint('CUSTOMER AUTH EMAIL: ${user?.email}');
    debugPrint('CUSTOMER SESSION EXISTS: ${session != null}');
    debugPrint('CUSTOMER SESSION EXPIRED: ${session?.isExpired}');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _supabase.rpc('get_my_fuel_customer_profile'),
        _supabase.rpc('get_my_fuel_requests'),
        _supabase.rpc('get_my_fuel_monthly_allowances'),
      ]);

      if (!mounted) return;

      final profiles = List<Map<String, dynamic>>.from(results[0] as List);

      setState(() {
        _profile = profiles.isEmpty ? null : profiles.first;
        _requests = List<Map<String, dynamic>>.from(results[1] as List);
        _allowances = List<Map<String, dynamic>>.from(results[2] as List);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDistricts() async {
    try {
      final districts = await _locationService.getDistricts();
      if (!mounted) return;
      setState(() => _districts = districts);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _selectDistrict(String? value) async {
    setState(() {
      _districtId = value;
      _omcId = null;
      _stationId = null;
      _omcs = [];
      _stations = [];
      _loadingLocations = value != null;
    });

    if (value == null) return;

    try {
      final omcs = await _locationService.getOmcsForDistrict(value);
      if (!mounted || _districtId != value) return;
      setState(() => _omcs = omcs);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && _districtId == value) {
        setState(() => _loadingLocations = false);
      }
    }
  }

  Future<void> _selectOmc(String? value) async {
    setState(() {
      _omcId = value;
      _stationId = null;
      _stations = [];
      _loadingLocations = value != null;
    });

    if (value == null || _districtId == null) return;

    final district = _districtId!;

    try {
      final stations = await _locationService.getStations(
        districtId: district,
        omcId: value,
      );

      if (!mounted || _districtId != district || _omcId != value) {
        return;
      }

      setState(() => _stations = stations);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && _omcId == value) {
        setState(() => _loadingLocations = false);
      }
    }
  }

  double _litres(String value) => double.tryParse(value.trim()) ?? 0;

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_districtId == null || _omcId == null || _stationId == null) {
      _showMessage('Select a district, OMC and filling station.');
      return;
    }

    final petrol = _litres(_petrolController.text);
    final diesel = _litres(_dieselController.text);

    if (petrol <= 0 && diesel <= 0) {
      _showMessage('Enter a petrol or diesel quantity.');
      return;
    }

    final items = <Map<String, dynamic>>[];

    if (petrol > 0) {
      items.add({'product': 'PETROL', 'litres': petrol});
    }

    if (diesel > 0) {
      items.add({'product': 'DIESEL', 'litres': diesel});
    }

    setState(() => _submitting = true);

    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    debugPrint('CUSTOMER AUTH USER: ${user?.id}');
    debugPrint('CUSTOMER AUTH EMAIL: ${user?.email}');
    debugPrint('CUSTOMER SESSION EXISTS: ${session != null}');
    debugPrint('CUSTOMER SESSION EXPIRED: ${session?.isExpired}');

    try {
      final requestId = await _supabase.rpc(
        'submit_registered_fuel_request',
        params: {
          'p_district_id': _districtId,
          'p_omc_id': _omcId,
          'p_station_id': _stationId,
          'p_reason': _reasonController.text.trim(),
          'p_items': items,
        },
      );

      // The RPC returns a UUID; fetch the customer-visible
      // reference from the authenticated request-history RPC.
      await _refresh();

      final matching = _requests.where(
        (request) => request['request_id'].toString() == requestId.toString(),
      );

      final request = matching.isEmpty ? null : matching.first;
      final reference =
          request?['request_number']?.toString() ?? requestId.toString();
      final status = request?['status']?.toString() ?? 'Submitted';

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Fuel Request Submitted'),
          content: Text(
            'Reference: $reference\n'
            'Status: $status\n\n'
            'Keep this reference for follow-up.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      _reasonController.clear();
      _petrolController.clear();
      _dieselController.clear();

      setState(() {
        _districtId = null;
        _omcId = null;
        _stationId = null;
        _omcs = [];
        _stations = [];
        _selectedTab = 1;
      });
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/container-fuels',
      (route) => false,
    );
  }

  Widget _newRequest() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'New Fuel Request',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _districtId,
            decoration: const InputDecoration(
              labelText: 'District',
              border: OutlineInputBorder(),
            ),
            items: _districts.map((district) {
              return DropdownMenuItem(
                value: district['id'].toString(),
                child: Text(district['name'].toString()),
              );
            }).toList(),
            onChanged: _submitting ? null : _selectDistrict,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _omcId,
            decoration: const InputDecoration(
              labelText: 'Oil Marketing Company (OMC)',
              border: OutlineInputBorder(),
            ),
            items: _omcs.map((omc) {
              return DropdownMenuItem(
                value: omc['id'].toString(),
                child: Text(omc['name'].toString()),
              );
            }).toList(),
            onChanged: _submitting || _districtId == null ? null : _selectOmc,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _stationId,
            decoration: const InputDecoration(
              labelText: 'Filling Station',
              border: OutlineInputBorder(),
            ),
            items: _stations.map((station) {
              return DropdownMenuItem(
                value: station['station_id'].toString(),
                child: Text(station['station_name'].toString()),
              );
            }).toList(),
            onChanged: _submitting || _omcId == null
                ? null
                : (value) => setState(() => _stationId = value),
          ),
          if (_loadingLocations) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          TextFormField(
            controller: _petrolController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Petrol (Litres)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _dieselController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Diesel (Litres)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason for Fuel Request',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if ((value ?? '').trim().length < 10) {
                return 'Enter a reason of at least 10 characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _submitting ? null : _submitRequest,
            icon: const Icon(Icons.send),
            label: Text(_submitting ? 'Submitting...' : 'Submit Fuel Request'),
            style: FilledButton.styleFrom(
              backgroundColor: MeraColors.green,
              padding: const EdgeInsets.all(18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _myRequests() {
    if (_requests.isEmpty) {
      return const Center(child: Text('No fuel requests submitted yet.'));
    }

    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final request in _requests) {
      final key = request['request_id'].toString();
      grouped.putIfAbsent(key, () => []).add(request);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'My Fuel Requests',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        for (final entries in grouped.values)
          Card(
            child: ListTile(
              title: Text(entries.first['request_number'].toString()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: ${entries.first['status']}'),
                  Text('Submitted: ${entries.first['created_at']}'),
                  for (final item in entries)
                    Text(
                      '${item['product']}: '
                      '${item['requested_litres']} L requested, '
                      '${item['approved_litres'] ?? 0} L approved',
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _monthlyAllowance() {
    if (_allowances.isEmpty) {
      return const Text('No active monthly fuel allowances configured.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Monthly Fuel Allowance',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        for (final allowance in _allowances)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allowance['product'].toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Monthly Limit: '
                    '${allowance['monthly_limit_litres']} L',
                  ),
                  Text(
                    'Approved: '
                    '${allowance['used_litres']} L',
                  ),
                  Text(
                    'Remaining: '
                    '${allowance['remaining_litres']} L',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MeraColors.background,
      appBar: AppBar(
        title: const Text('MERA Customer Portal'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 950),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, '
                                '${_profile?['applicant_name'] ?? 'Customer'}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_profile?['company_name'] != null)
                                Text(_profile!['company_name'].toString()),
                              Text(_profile?['email']?.toString() ?? ''),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _tabButton('New Fuel Request', 0),
                          _tabButton('My Requests', 1),
                          _tabButton('Monthly Allowance', 2),
                          _tabButton('My Documents', 3),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (_selectedTab == 0)
                        _newRequest()
                      else if (_selectedTab == 1)
                        _myRequests()
                      else if (_selectedTab == 2)
                        _monthlyAllowance()
                      else if (_profile?['id'] != null)
                        CustomerDocumentsTab(
                          applicantId: _profile!['id'].toString(),
                          verificationStatus:
                              _profile?['verification_status']?.toString() ??
                              'PENDING',
                        )
                      else
                        const Text('Customer profile not found.'),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _tabButton(String label, int index) {
    return OutlinedButton(
      onPressed: () => setState(() => _selectedTab = index),
      child: Text(label),
    );
  }
}
