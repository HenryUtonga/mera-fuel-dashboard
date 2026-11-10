import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class FuelRequestsReviewPage extends StatefulWidget {
  const FuelRequestsReviewPage({super.key});

  @override
  State<FuelRequestsReviewPage> createState() => _FuelRequestsReviewPageState();
}

class _FuelRequestsReviewPageState extends State<FuelRequestsReviewPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _client.rpc('list_fuel_requests_for_review');
      if (!mounted) return;
      setState(() {
        _requests = (response as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _requests
        .where((r) => _filter == 'ALL' || r['status'] == _filter)
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Fuel Requests',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final f in [
                  'ALL',
                  'PENDING_MERA_APPROVAL',
                  'APPROVED',
                  'REJECTED',
                ])
                  ChoiceChip(
                    label: Text(f == 'ALL' ? 'All' : f.replaceAll('_', ' ')),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(
                  'Unable to load requests: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? const Center(
                      child: Text(
                        'No requests available for this filter or your permissions.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final r = visible[i];
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${r['request_number'] ?? ''}  •  ${r['applicant_name'] ?? ''}',
                            ),
                            subtitle: Text(
                              '${r['status'] ?? ''}  •  ${r['applicant_type'] ?? ''}\n${r['created_at'] ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _RequestReviewDetails(request: r),
                                ),
                              );
                              if (mounted) _load();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestReviewDetails extends StatefulWidget {
  const _RequestReviewDetails({required this.request});
  final Map<String, dynamic> request;

  @override
  State<_RequestReviewDetails> createState() => _RequestReviewDetailsState();
}

class _RequestReviewDetailsState extends State<_RequestReviewDetails> {
  final _client = Supabase.instance.client;
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _litres = {};
  final Map<String, String?> _stations = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _eligibleStations = [];
  List<Map<String, dynamic>> _documents = [];
  final Set<String> _openedDocumentIds = {};
  String? _openingDocumentId;
  bool _loading = true;
  bool _saving = false;
  bool _documentsVerified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _litres.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = widget.request['id'].toString();
      final districtId = widget.request['district_id'].toString();
      final results = await Future.wait([
        _client.rpc(
          'get_fuel_request_items_for_review',
          params: {'p_request_id': id},
        ),
        _client.rpc(
          'get_fuel_request_documents_for_review',
          params: {'p_request_id': id},
        ),
        _client.rpc(
          'get_fuel_request_stations',
          params: {'p_district_id': districtId},
        ),
      ]);
      if (!mounted) return;
      final items = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final documents = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final stations = (results[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      for (final item in items) {
        final itemId = item['id'].toString();
        _litres[itemId] = TextEditingController(
          text:
              item['approved_litres']?.toString() ??
              item['requested_litres'].toString(),
        );
        _stations[itemId] =
            stations.any(
              (s) =>
                  s['station_id'].toString() ==
                  widget.request['preferred_station_id']?.toString(),
            )
            ? widget.request['preferred_station_id'].toString()
            : (stations.isNotEmpty
                  ? stations.first['station_id'].toString()
                  : null);
      }
      setState(() {
        _items = items;
        _documents = documents;
        _eligibleStations = stations;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _allDocumentsOpened =>
      _documents.isNotEmpty &&
      _documents.every(
        (d) => _openedDocumentIds.contains(d['id'].toString()),
      ) &&
      _documents.any((d) => d['document_type'] == 'IDENTIFICATION') &&
      _documents.any((d) => d['document_type'] == 'PROOF_OF_NEED');

  Future<void> _openDocument(Map<String, dynamic> document) async {
    if (_openingDocumentId != null) return;
    final id = document['id'].toString();
    setState(() {
      _openingDocumentId = id;
      _error = null;
    });
    try {
      final bucket = document['storage_bucket'].toString();
      final path = document['storage_path'].toString();
      if (bucket != 'fuel-request-documents' || path.isEmpty) {
        throw StateError('Invalid document storage location.');
      }
      // Supabase enforces the authenticated user's Storage SELECT policy
      // before issuing a signed URL. This URL expires after 60 seconds.
      final signedUrl = await _client.storage
          .from(bucket)
          .createSignedUrl(path, 60);
      final launched = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('Unable to open the document.');
      if (!mounted) return;
      setState(() => _openedDocumentIds.add(id));
    } catch (e) {
      if (mounted) setState(() => _error = 'Unable to open document: $e');
    } finally {
      if (mounted) setState(() => _openingDocumentId = null);
    }
  }

  Future<void> _approve() async {
    if (_saving || !_allDocumentsOpened || !_documentsVerified) return;
    final approvals = <Map<String, dynamic>>[];
    for (final item in _items) {
      final id = item['id'].toString();
      final quantity = double.tryParse(_litres[id]!.text.trim());
      final requested = double.tryParse(item['requested_litres'].toString());
      final station = _stations[id];
      if (quantity == null ||
          requested == null ||
          quantity <= 0 ||
          quantity > requested ||
          (quantity * 100 - (quantity * 100).round()).abs() > 0.00001 ||
          station == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter valid approved litres (up to requested amount) and select a station for each product.',
            ),
          ),
        );
        return;
      }
      approvals.add({
        'item_id': id,
        'approved_litres': quantity,
        'allocations': [
          {'station_id': station, 'litres': quantity},
        ],
      });
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm approval'),
        content: const Text(
          'This action approves the request and creates fuel allocations. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc(
        'approve_fuel_request',
        params: {
          'p_request_id': widget.request['id'].toString(),
          'p_approvals': approvals,
          'p_review_notes': _notes.text.trim().isEmpty
              ? null
              : _notes.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved successfully.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Approval failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final canApprove =
        r['can_approve'] == true && r['status'] == 'PENDING_MERA_APPROVAL';
    return Scaffold(
      appBar: AppBar(
        title: Text(r['request_number']?.toString() ?? 'Fuel request'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  r['applicant_name']?.toString() ?? '',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                for (final key in [
                  'status',
                  'applicant_type',
                  'email',
                  'phone_number',
                  'request_reason',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${key.replaceAll('_', ' ').toUpperCase()}: ${r[key] ?? '—'}',
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'Fuel products and allocations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  SelectableText(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                for (final item in _items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['product']} — requested ${item['requested_litres']} L',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (canApprove) ...[
                            TextField(
                              controller: _litres[item['id'].toString()],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Approved litres',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _stations[item['id'].toString()],
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Allocate to station',
                                border: OutlineInputBorder(),
                              ),
                              items: _eligibleStations
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s['station_id'].toString(),
                                      child: Text(
                                        '${s['station_name']} (${s['omc_name']})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _stations[item['id'].toString()] = value,
                              ),
                            ),
                          ] else
                            Text(
                              'Approved: ${item['approved_litres'] ?? 'Pending'} L',
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Supporting documents',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_documents.isEmpty)
                  const Text(
                    'No supporting documents available. Approval is blocked.',
                  ),
                for (final document in _documents)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _openedDocumentIds.contains(document['id'].toString())
                            ? Icons.check_circle_outline
                            : Icons.description_outlined,
                      ),
                      title: Text(
                        document['document_type'].toString().replaceAll(
                          '_',
                          ' ',
                        ),
                      ),
                      subtitle: Text(
                        document['file_name']?.toString() ?? 'Document',
                      ),
                      trailing: _openingDocumentId == document['id'].toString()
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new),
                      onTap: _openingDocumentId == null
                          ? () => _openDocument(document)
                          : null,
                    ),
                  ),
                if (canApprove && !_allDocumentsOpened)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Open every uploaded document before confirming verification. Identification and proof of need are required.',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                if (canApprove) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Review notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _documentsVerified,
                    onChanged: _allDocumentsOpened
                        ? (value) => setState(
                            () => _documentsVerified = value ?? false,
                          )
                        : null,
                    title: const Text(
                      'I have independently verified the supporting documents',
                    ),
                    subtitle: const Text(
                      'Confirm only after checking the contents and authenticity of every supporting document.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton.icon(
                    onPressed:
                        _saving ||
                            !_documentsVerified ||
                            !_allDocumentsOpened ||
                            _eligibleStations.isEmpty ||
                            _items.isEmpty
                        ? null
                        : _approve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_saving ? 'Approving…' : 'Approve request'),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Rejection and permanent document-verification records are not implemented yet. Only approve after independent verification.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ],
            ),
    );
  }
}
