
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StationConfirmationPage extends StatefulWidget {
  const StationConfirmationPage({super.key});

  @override
  State<StationConfirmationPage> createState() =>
      _StationConfirmationPageState();
}

class _StationConfirmationPageState
    extends State<StationConfirmationPage> {
  final _litresController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _completed = false;

  String? _error;
  Map<String, dynamic>? _details;

  late final String _token;
  late final String _action;

  @override
  void initState() {
    super.initState();

    final fragment = Uri.base.fragment;
    final fragmentQuery = fragment.contains('?')
        ? fragment.substring(fragment.indexOf('?') + 1)
        : fragment;

    final fragmentParams = Uri.splitQueryString(
      fragmentQuery.startsWith('token=')
          ? fragmentQuery
          : fragmentQuery.contains('token=')
              ? fragmentQuery
              : '',
    );

    _token = fragmentParams['token'] ?? '';
    _action = fragmentParams['action'] == 'not_fueled'
        ? 'not_fueled'
        : 'confirm';

    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_token)) {
      _loading = false;
      _error = 'This confirmation link is invalid.';
    } else {
      _loadDetails();
    }
  }

  Future<Map<String, dynamic>> _callFunction(
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'confirm-fuel-station-dispensing',
      body: body,
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception('The request could not be completed.');
    }

    final data = response.data;

    if (data is! Map) {
      throw Exception('Unexpected response from the server.');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<void> _loadDetails() async {
    try {
      final result = await _callFunction({
        'action': 'lookup',
        'token': _token,
      });

      if (!mounted) return;

final authorization = result['authorization'];

if (result['success'] != true ||
    authorization is! Map) {
  throw Exception('Invalid authorization response.');
}

setState(() {
  _details = Map<String, dynamic>.from(authorization);
  _error = null;
  _loading = false;
});
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'Unable to load this authorization. '
            'The link may have expired or already been used.';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || _completed) return;

    final body = <String, dynamic>{
      'action': _action,
      'token': _token,
      'notes': _notesController.text.trim(),
    };

    if (_action == 'confirm') {
      final litres = double.tryParse(
        _litresController.text.trim(),
      );

      if (litres == null || !litres.isFinite || litres <= 0) {
        setState(() {
          _error = 'Enter a valid quantity greater than zero.';
        });
        return;
      }

      body['confirmed_litres'] = litres;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _callFunction(body);

      if (!mounted) return;

      setState(() {
        _completed = true;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _submitting = false;
        _error =
            'Your response could not be recorded. '
            'Please check the details and try again.';
      });
    }
  }

  String _value(String key) {
    return _details?[key]?.toString() ?? '—';
  }

  @override
  void dispose() {
    _litresController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _action == 'confirm';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        title: const Text('MERA Fuel Authorization'),
        backgroundColor: const Color(0xFF123B69),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _completed
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 56,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isConfirm
                                    ? 'Fueling Confirmed'
                                    : 'Not Fueled Report Submitted',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isConfirm
                                    ? 'The fueling information has been recorded.'
                                    : 'Your report has been recorded '
                                      'for MERA review. The allocation '
                                      'has not been cancelled.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isConfirm
                                    ? 'Confirm Fueling'
                                    : 'Report Not Fueled',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 16),

                              if (_error != null) ...[
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (_details != null) ...[
                                Text(
                                  'Request: ${_value('request_number')}',
                                ),
                                Text(
                                  'Station: ${_value('station_name')}',
                                ),
                                Text(
                                  'Product: ${_value('product')}',
                                ),
                                Text(
                                  'Authorized: ${_value('allocated_litres')} litres',
                                ),
                                const SizedBox(height: 24),

                                if (isConfirm) ...[
                                  TextField(
                                    controller: _litresController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration:
                                        const InputDecoration(
                                          labelText:
                                              'Actual litres dispensed',
                                          border:
                                              OutlineInputBorder(),
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                TextField(
                                  controller: _notesController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    labelText: isConfirm
                                        ? 'Notes (optional)'
                                        : 'Reason (optional)',
                                    border:
                                        const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                FilledButton(
                                  onPressed:
                                      _submitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isConfirm
                                        ? const Color(0xFF167347)
                                        : const Color(0xFFA83232),
                                    padding:
                                        const EdgeInsets.all(16),
                                  ),
                                  child: Text(
                                    _submitting
                                        ? 'Submitting...'
                                        : isConfirm
                                            ? 'Submit Fueling Confirmation'
                                            : 'Submit Not Fueled Report',
                                  ),
                                ),
                              ],
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
