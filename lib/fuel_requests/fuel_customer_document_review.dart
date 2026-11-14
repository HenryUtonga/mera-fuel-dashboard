import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class FuelCustomerDocumentReview extends StatefulWidget {
  const FuelCustomerDocumentReview({
    super.key,
    required this.applicantId,
    required this.customerName,
  });

  final String applicantId;
  final String customerName;

  @override
  State<FuelCustomerDocumentReview> createState() =>
      _FuelCustomerDocumentReviewState();
}

class _FuelCustomerDocumentReviewState
    extends State<FuelCustomerDocumentReview> {
  final _supabase = Supabase.instance.client;

  static const _mandatory = {
    'COMPANY_REGISTRATION',
    'APPLICANT_ID',
    'PROOF_OF_NEED',
  };

  static const _labels = {
    'COMPANY_REGISTRATION': 'Company Registration Certificate',
    'APPLICANT_ID': 'Manager / Applicant National ID',
    'PROOF_OF_NEED': 'Proof of Need for Fuel',
    'ATTACHMENT_1': 'Additional Attachment 1',
    'ATTACHMENT_2': 'Additional Attachment 2',
    'ATTACHMENT_3': 'Additional Attachment 3',
  };

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _documents = [];

  // Customer verification
String _verificationStatus = 'PENDING';
String? _verifiedBy;
String? _verifiedByName;
DateTime? _verifiedAt;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    try {
      final result = await _supabase.rpc(
        'admin_get_fuel_applicant_verification',
        params: {'p_applicant_id': widget.applicantId},
      );

      final rows = List<Map<String, dynamic>>.from(result);

      if (!mounted || rows.isEmpty) return;

      final customer = rows.first;

      setState(() {
        _verificationStatus =
            customer['verification_status']?.toString() ?? 'PENDING';

        _verifiedBy = customer['verified_by']?.toString();
        _verifiedByName = customer['verified_by_name']?.toString();
        _verifiedAt = customer['verified_at'] == null
            ? null
            : DateTime.tryParse(customer['verified_at'].toString());
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage('Unable to load customer verification: $e');
    }
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _supabase.rpc(
        'admin_get_fuel_applicant_documents',
        params: {'p_applicant_id': widget.applicantId},
      );

      if (!mounted) return;

      setState(() {
        _documents = List<Map<String, dynamic>>.from(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _viewDocument(Map<String, dynamic> document) async {
    try {
      final path = document['storage_path'].toString();

      final signedUrl = await _supabase.storage
          .from('fuel-customer-documents')
          .createSignedUrl(path, 120);

      final opened = await launchUrl(
        Uri.parse(signedUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Unable to open document.');
      }
    } catch (e) {
      _showMessage('Unable to view document: $e');
    }
  }

  Future<void> _verifyCustomer() async {
    if (_busy || _loading || _verificationStatus == 'VERIFIED') {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify Customer'),
        content: Text(
          'Are you sure you want to verify ${widget.customerName}? '
          'This confirms that all mandatory supporting documents '
          'have been reviewed and approved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verify Customer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      await _supabase.rpc(
        'verify_fuel_applicant',
        params: {'p_applicant_id': widget.applicantId},
      );

      await _loadVerificationStatus();

      _showMessage('Customer verified successfully.');
    } catch (e) {
      _showMessage('Customer verification failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reviewDocument(
    Map<String, dynamic> document,
    String status,
  ) async {
    if (_busy) return;

    final notesController = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            status == 'APPROVED' ? 'Approve Document' : 'Reject Document',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _labels[document['document_type']] ??
                    document['document_type'].toString(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: status == 'REJECTED'
                      ? 'Reason for rejection (required)'
                      : 'Review notes (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (status == 'REJECTED' &&
                    notesController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(status == 'APPROVED' ? 'Approve' : 'Reject'),
            ),
          ],
        ),
      );

      final notes = notesController.text.trim();

      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);

      await _supabase.rpc(
        'review_fuel_applicant_document',
        params: {
          'p_document_id': document['id'],
          'p_review_status': status,
          'p_review_notes': notes.isEmpty ? null : notes,
        },
      );

      _showMessage('Document marked as $status.');
      await _loadDocuments();
    } catch (e) {
      _showMessage('Document review failed: $e');
    } finally {
      notesController.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approvedMandatory = _mandatory.where((type) {
      return _documents.any(
        (d) => d['document_type'] == type && d['review_status'] == 'APPROVED',
      );
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Verify Documents - ${widget.customerName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy || _loading ? null : _loadDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: SelectableText(_error!))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Mandatory documents approved: '
                  '$approvedMandatory / 3',
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                const SizedBox(height: 12),

                // Customer verification status
                Row(
                  children: [
                    Icon(
                      _verificationStatus == 'VERIFIED'
                          ? Icons.verified
                          : Icons.pending_outlined,
                      color: _verificationStatus == 'VERIFIED'
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Customer Verification: $_verificationStatus',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),

                if (_verificationStatus == 'VERIFIED' &&
                    _verifiedAt != null) ...[
                  const SizedBox(height: 8),
                  Text('Verified on: ${_verifiedAt!.toLocal()}'),
                ],

if (_verificationStatus == 'VERIFIED' && _verifiedBy != null) ...[
  const SizedBox(height: 4),
  Text('Verified by: ${_verifiedByName ?? _verifiedBy}'),
],

                const SizedBox(height: 8),
                const Text(
                  'Customer verification is a separate '
                  'administrative decision.',
                ),

                const SizedBox(height: 16),

                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed:
                        _busy ||
                            _loading ||
                            _verificationStatus == 'VERIFIED' ||
                            approvedMandatory != 3
                        ? null
                        : _verifyCustomer,
                    icon: Icon(
                      _verificationStatus == 'VERIFIED'
                          ? Icons.verified
                          : Icons.verified_user_outlined,
                    ),
                    label: Text(
                      _verificationStatus == 'VERIFIED'
                          ? 'Customer Verified'
                          : 'Verify Customer',
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (_documents.isEmpty)
                  const Text('No documents uploaded.')
                else
                  for (final document in _documents)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _labels[document['document_type']] ??
                                  document['document_type'].toString(),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(document['original_filename'].toString()),
                            const SizedBox(height: 6),
                            Text('Status: ${document['review_status']}'),
                            if (document['review_notes'] != null)
                              Text('Notes: ${document['review_notes']}'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _viewDocument(document),
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: const Text('View'),
                                ),

                                FilledButton.icon(
                                  onPressed:
                                      _busy ||
                                          document['review_status'] ==
                                              'APPROVED'
                                      ? null
                                      : () => _reviewDocument(
                                          document,
                                          'APPROVED',
                                        ),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    document['review_status'] == 'APPROVED'
                                        ? 'Approved'
                                        : 'Approve',
                                  ),
                                ),

                                OutlinedButton.icon(
                                  onPressed:
                                      _busy ||
                                          document['review_status'] ==
                                              'REJECTED'
                                      ? null
                                      : () => _reviewDocument(
                                          document,
                                          'REJECTED',
                                        ),
                                  icon: const Icon(Icons.close),
                                  label: Text(
                                    document['review_status'] == 'REJECTED'
                                        ? 'Rejected'
                                        : 'Reject',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
