import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';

class CustomerDocumentsTab extends StatefulWidget {
  final String applicantId;
  final String verificationStatus;

  const CustomerDocumentsTab({
    super.key,
    required this.applicantId,
    required this.verificationStatus,
  });

  @override
  State<CustomerDocumentsTab> createState() => _CustomerDocumentsTabState();
}

class _CustomerDocumentsTabState extends State<CustomerDocumentsTab> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _documents = [];
  bool _loading = true;
  String? _uploadingType;
  String? _error;

  static const _documentTypes = [
    ('COMPANY_REGISTRATION', 'Company Registration Certificate', true),
    ('APPLICANT_ID', 'Manager / Applicant National ID', true),
    ('PROOF_OF_NEED', 'Proof of Need for Fuel', true),
    ('ATTACHMENT_1', 'Additional Attachment 1', false),
    ('ATTACHMENT_2', 'Additional Attachment 2', false),
    ('ATTACHMENT_3', 'Additional Attachment 3', false),
  ];

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _supabase.rpc('get_my_fuel_customer_documents');

      if (!mounted) return;

      setState(() {
        _documents = List<Map<String, dynamic>>.from(result as List);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _findDocument(String type) {
    for (final doc in _documents) {
      if (doc['document_type'] == type) return doc;
    }
    return null;
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _uploadDocument(String type) async {
    if (_uploadingType != null) return;

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (files.isEmpty) return;

      final file = files.first;

      final Uint8List bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        _message('Unable to read the selected file.');
        return;
      }

      if (bytes.length > 10485760) {
        _message('Maximum document size is 10 MB.');
        return;
      }

      final extension = file.extension?.toLowerCase();

      if (!['pdf', 'jpg', 'jpeg', 'png'].contains(extension)) {
        _message('Only PDF, JPG and PNG files are supported.');
        return;
      }

      // Check file signatures rather than trusting extensions alone.
      final isPdf =
          bytes.length >= 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2D;

      final isJpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;

      final isPng =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A;

      final validSignature = switch (extension) {
        'pdf' => isPdf,
        'jpg' || 'jpeg' => isJpeg,
        'png' => isPng,
        _ => false,
      };

      if (!validSignature) {
        _message('File content does not match its extension.');
        return;
      }

      final mimeType = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'image/png',
      };

      final uuid = _supabase.auth.currentUser?.id;
      if (uuid == null) {
        _message('Your session has expired. Please sign in again.');
        return;
      }

      setState(() => _uploadingType = type);

      final uniqueId = _generateUuid();
      final path = '${widget.applicantId}/$type/$uniqueId.$extension';

      await _supabase.storage
          .from('fuel-customer-documents')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );

      await _supabase.rpc(
        'submit_fuel_customer_document',
        params: {
          'p_document_type': type,
          'p_storage_path': path,
          'p_original_filename': file.name,
          'p_mime_type': mimeType,
          'p_file_size_bytes': bytes.length,
        },
      );

      await _loadDocuments();
      _message('Document uploaded successfully.');
    } catch (e) {
      _message('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingType = null);
    }
  }

  String _generateUuid() {
    // Supabase/PostgREST-compatible random UUID v4.
    final values = List<int>.generate(16, (_) => _randomByte());

    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;

    final hex = values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  final Random _secureRandom = Random.secure();

  int _randomByte() {
    return _secureRandom.nextInt(256);
  }

  Future<void> _viewDocument(Map<String, dynamic> doc) async {
    try {
      final signedUrl = await _supabase.storage
          .from('fuel-customer-documents')
          .createSignedUrl(doc['storage_path'].toString(), 120);

      final uri = Uri.parse(signedUrl);

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        _message('Unable to open the document.');
      }
    } catch (e) {
      _message('Unable to open document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Column(
        children: [
          Text(_error!),
          TextButton(onPressed: _loadDocuments, child: const Text('Retry')),
        ],
      );
    }

    final mandatoryCount = _documentTypes
        .where((item) => item.$3)
        .where((item) => _findDocument(item.$1) != null)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'My Supporting Documents',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text('Verification Status: ${widget.verificationStatus}'),
        Text('Mandatory documents: $mandatoryCount / 3'),
        const SizedBox(height: 20),
        for (final item in _documentTypes)
          _documentCard(item.$1, item.$2, item.$3),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loadDocuments,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh Documents'),
        ),
      ],
    );
  }

  Widget _documentCard(String type, String label, bool mandatory) {
    final doc = _findDocument(type);
    final uploading = _uploadingType == type;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label ${mandatory ? "(Required)" : "(Optional)"}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              doc == null
                  ? 'Not uploaded'
                  : 'File: ${doc['original_filename']}',
            ),
            if (doc != null) ...[
              Text('Review: ${doc['review_status']}'),
              if (doc['review_notes'] != null)
                Text('MERA feedback: ${doc['review_notes']}'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _uploadingType != null
                      ? null
                      : () => _uploadDocument(type),
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    uploading
                        ? 'Uploading...'
                        : doc == null
                        ? 'Upload'
                        : 'Replace',
                  ),
                ),
                if (doc != null)
                  OutlinedButton.icon(
                    onPressed: () => _viewDocument(doc),
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                  ),
              ],
            ),
            if (uploading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
