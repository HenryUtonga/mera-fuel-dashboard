import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String _filter = 'PENDING_MERA_APPROVAL';

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
                    'Fuel Request Approvals',
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
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in const [
                  'PENDING_MERA_APPROVAL',
                  'APPROVED',
                  'REJECTED',
                  'ALL',
                ])
                  ChoiceChip(
                    label: Text(_statusLabel(filter)),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 16),
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
                  ? Center(
                      child: Text(
                        _filter == 'PENDING_MERA_APPROVAL'
                            ? 'No requests currently pending MERA approval.'
                            : 'No requests available for this filter or your permissions.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final request = visible[index];
                        final status = (request['status'] ?? '').toString();
                        final applicant =
                            (request['applicant_name'] ?? 'Unknown applicant')
                                .toString();
                        final type = (request['applicant_type'] ?? '')
                            .toString();
                        final email = (request['email'] ?? '').toString();
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      _RequestReviewDetails(request: request),
                                ),
                              );
                              if (mounted) _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        (request['request_number'] ??
                                                'No reference')
                                            .toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF176B42),
                                        ),
                                      ),
                                      _RequestStatusBadge(status: status),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    applicant,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (email.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      email,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 24,
                                    runSpacing: 8,
                                    children: [
                                      _RequestMeta(
                                        icon: Icons.person_outline,
                                        text: _applicantTypeLabel(type),
                                      ),
                                      _RequestMeta(
                                        icon: Icons.schedule_outlined,
                                        text: _malawiDate(
                                          request['created_at'],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 28),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'View request',
                                        style: TextStyle(
                                          color: Color(0xFF176B42),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Color(0xFF176B42),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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

String _statusLabel(String status) {
  switch (status) {
    case 'PENDING_MERA_APPROVAL':
      return 'Pending MERA Approval';
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    case 'ALL':
      return 'All';
    default:
      return status.replaceAll('_', ' ');
  }
}

String _applicantTypeLabel(String type) {
  if (type == 'ONCE_OFF') return 'Once-off applicant';
  if (type == 'REGISTERED') return 'Registered customer';
  return type.replaceAll('_', ' ');
}

String _malawiDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Date unavailable';
  final local = parsed.toUtc().add(const Duration(hours: 2));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)} CAT';
}

class _RequestStatusBadge extends StatelessWidget {
  const _RequestStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color background;
    switch (status) {
      case 'APPROVED':
        color = Colors.green.shade800;
        background = Colors.green.shade50;
        break;
      case 'REJECTED':
        color = Colors.red.shade800;
        background = Colors.red.shade50;
        break;
      default:
        color = Colors.orange.shade900;
        background = Colors.orange.shade50;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RequestMeta extends StatelessWidget {
  const _RequestMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: Colors.grey.shade600),
      const SizedBox(width: 6),
      Text(text),
    ],
  );
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF176B42)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    ),
  );
}

class _RequestField extends StatelessWidget {
  const _RequestField({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value.isEmpty ? 'Not provided' : value,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
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

  Future<void> _reject() async {
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject fuel request'),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 4,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            hintText: 'Explain why this request is being rejected',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.length < 5) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a reason of at least 5 characters.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Confirm rejection'),
          ),
        ],
      ),
    );

    reasonController.dispose();

    if (reason == null || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _client.rpc(
        'reject_fuel_request',
        params: {
          'p_request_id': widget.request['id'].toString(),
          'p_rejection_reason': reason,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fuel request rejected successfully.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rejection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final canApprove =
        r['can_approve'] == true && r['status'] == 'PENDING_MERA_APPROVAL';
    final status = (r['status'] ?? '').toString();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        title: Text(r['request_number']?.toString() ?? 'Fuel request'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            (r['applicant_name'] ?? 'Unknown applicant')
                                .toString(),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          _RequestStatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      _RequestSection(
                        title: 'Applicant information',
                        icon: Icons.person_outline,
                        child: Wrap(
                          spacing: 32,
                          runSpacing: 4,
                          children: [
                            SizedBox(
                              width: 260,
                              child: _RequestField(
                                label: 'Applicant type',
                                value: _applicantTypeLabel(
                                  (r['applicant_type'] ?? '').toString(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: _RequestField(
                                label: 'Email',
                                value: (r['email'] ?? '').toString(),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: _RequestField(
                                label: 'Phone number',
                                value: (r['phone_number'] ?? '').toString(),
                              ),
                            ),
                            SizedBox(
                              width: 260,
                              child: _RequestField(
                                label: 'Submitted (Malawi time)',
                                value: _malawiDate(r['created_at']),
                              ),
                            ),
                            SizedBox(
                              width: 600,
                              child: _RequestField(
                                label: 'Reason for request',
                                value: (r['request_reason'] ?? '').toString(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RequestSection(
                        title: 'Fuel products and allocations',
                        icon: Icons.local_gas_station_outlined,
                        child: _items.isEmpty
                            ? const Text('No fuel products available.')
                            : Column(
                                children: [
                                  for (final item in _items)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item['product']} - Requested: '
                                            '${item['requested_litres']} L',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if (canApprove) ...[
                                            TextField(
                                              controller:
                                                  _litres[item['id']
                                                      .toString()],
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
                                              initialValue:
                                                  _stations[item['id']
                                                      .toString()],
                                              isExpanded: true,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Allocate to station',
                                                border: OutlineInputBorder(),
                                              ),
                                              items: _eligibleStations
                                                  .map(
                                                    (
                                                      station,
                                                    ) => DropdownMenuItem<String>(
                                                      value:
                                                          station['station_id']
                                                              .toString(),
                                                      child: Text(
                                                        '${station['station_name']} (${station['omc_name']})',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (value) => setState(
                                                () =>
                                                    _stations[item['id']
                                                            .toString()] =
                                                        value,
                                              ),
                                            ),
                                          ] else
                                            Text(
                                              'Approved: ${item['approved_litres'] ?? 'Pending'} L',
                                            ),
                                          const Divider(height: 20),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      _RequestSection(
                        title: 'Supporting documents',
                        icon: Icons.description_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_documents.isEmpty)
                              const Text(
                                'No supporting documents available. Approval is blocked.',
                              ),
                            for (final document in _documents)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _openedDocumentIds.contains(
                                        document['id'].toString(),
                                      )
                                      ? Icons.check_circle_outline
                                      : Icons.description_outlined,
                                ),
                                title: Text(
                                  document['document_type']
                                      .toString()
                                      .replaceAll('_', ' '),
                                ),
                                subtitle: Text(
                                  document['file_name']?.toString() ??
                                      'Document',
                                ),
                                trailing:
                                    _openingDocumentId ==
                                        document['id'].toString()
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.open_in_new),
                                onTap: _openingDocumentId == null
                                    ? () => _openDocument(document)
                                    : null,
                              ),
                            if (canApprove && !_allDocumentsOpened)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Open every uploaded document before confirming '
                                  'verification. Identification and proof of need are required.',
                                  style: TextStyle(color: Colors.deepOrange),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canApprove)
                        _RequestSection(
                          title: 'Review and decision',
                          icon: Icons.fact_check_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                contentPadding: EdgeInsets.zero,
                                value: _documentsVerified,
                                onChanged: _allDocumentsOpened
                                    ? (value) => setState(
                                        () =>
                                            _documentsVerified = value ?? false,
                                      )
                                    : null,
                                title: const Text(
                                  'I have independently verified the supporting documents',
                                ),
                                subtitle: const Text(
                                  'Confirm only after checking the contents '
                                  'and authenticity of every supporting document.',
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  FilledButton.icon(
                                    onPressed:
                                        _saving ||
                                            !_documentsVerified ||
                                            !_allDocumentsOpened ||
                                            _eligibleStations.isEmpty ||
                                            _items.isEmpty
                                        ? null
                                        : _approve,
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                    ),
                                    label: Text(
                                      _saving
                                          ? 'Approving...'
                                          : 'Approve request',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _saving ? null : _reject,
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Reject request'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Approval requires document verification. '
                                'Rejection requires a reason.',
                                style: TextStyle(color: Colors.deepOrange),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
