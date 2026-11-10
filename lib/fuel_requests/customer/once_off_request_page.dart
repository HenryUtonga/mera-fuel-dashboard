import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/mera_theme.dart';

import '../services/fuel_request_location_service.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:http_parser/http_parser.dart';

class OnceOffRequestPage extends StatefulWidget {
  const OnceOffRequestPage({super.key});

  @override
  State<OnceOffRequestPage> createState() => _OnceOffRequestPageState();
}

class _OnceOffRequestPageState extends State<OnceOffRequestPage> {
  final _formKey = GlobalKey<FormState>();

  final _locationService = FuelRequestLocationService();
  bool _submitting = false;
  String? _submissionId;
  String? _submittedReference;

  void _markFormChanged() {
    if (!_submitting && _submittedReference == null) {
      _submissionId = null;
    }
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameController,
      _phoneController,
      _emailController,
      _reasonController,
      _petrolLitresController,
      _dieselLitresController,
    ]) {
      controller.addListener(_markFormChanged);
    }
    _loadDistricts();
  }

  Future<void> _loadDistricts() async {
    setState(() {
      _loadingDistricts = true;
      _locationError = null;
    });

    try {
      final districts = await _locationService.getDistricts();

      if (!mounted) return;

      setState(() {
        _districts = districts;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _locationError = 'Unable to load districts: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDistricts = false;
        });
      }
    }
  }

  Future<void> _selectDistrict(String? districtId) async {
    _markFormChanged();
    setState(() {
      _selectedDistrictId = districtId;
      _selectedOmcId = null;
      _selectedStationId = null;
      _omcs = [];
      _stations = [];
      _locationError = null;
      _loadingOmcs = districtId != null;
    });

    if (districtId == null) return;

    try {
      final omcs = await _locationService.getOmcsForDistrict(districtId);

      if (!mounted || _selectedDistrictId != districtId) return;

      setState(() {
        _omcs = omcs;
      });
    } catch (error) {
      if (!mounted || _selectedDistrictId != districtId) return;

      setState(() {
        _locationError = 'Unable to load OMCs: $error';
      });
    } finally {
      if (mounted && _selectedDistrictId == districtId) {
        setState(() {
          _loadingOmcs = false;
        });
      }
    }
  }

  Future<void> _selectOmc(String? omcId) async {
    _markFormChanged();
    setState(() {
      _selectedOmcId = omcId;
      _selectedStationId = null;
      _stations = [];
      _locationError = null;
      _loadingStations = omcId != null;
    });

    if (omcId == null || _selectedDistrictId == null) return;

    final districtId = _selectedDistrictId!;

    try {
      final stations = await _locationService.getStations(
        districtId: districtId,
        omcId: omcId,
      );

      if (!mounted ||
          _selectedDistrictId != districtId ||
          _selectedOmcId != omcId) {
        return;
      }

      setState(() {
        _stations = stations;
      });
    } catch (error) {
      if (!mounted ||
          _selectedDistrictId != districtId ||
          _selectedOmcId != omcId) {
        return;
      }

      setState(() {
        _locationError = 'Unable to load filling stations: $error';
      });
    } finally {
      if (mounted &&
          _selectedDistrictId == districtId &&
          _selectedOmcId == omcId) {
        setState(() {
          _loadingStations = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _districts = [];
  List<Map<String, dynamic>> _omcs = [];
  List<Map<String, dynamic>> _stations = [];

  String? _selectedDistrictId;
  String? _selectedOmcId;
  String? _selectedStationId;

  bool _loadingDistricts = false;
  bool _loadingOmcs = false;
  bool _loadingStations = false;
  String? _locationError;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _reasonController = TextEditingController();
  // Fuel quantities requested by the customer
  final _petrolLitresController = TextEditingController();
  final _dieselLitresController = TextEditingController();
  // Selected customer documents
  PlatformFile? _identificationDocument;
  PlatformFile? _proofOfNeedDocument;
  PlatformFile? _companyRegistrationDocument;

  // Maximum permitted file size: 10 MB
  static const int _maxDocumentSize = 10 * 1024 * 1024;

  Future<void> _pickDocument(String documentType) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );

      if (files.isEmpty) {
        return;
      }

      final file = files.first;

      const allowedExtensions = {'pdf', 'jpg', 'jpeg', 'png', 'webp'};

      final extension = file.extension?.toLowerCase();

      if (!allowedExtensions.contains(extension)) {
        throw Exception('Invalid file type. Select PDF, JPG, PNG or WebP.');
      }

      // Check the actual file size.
      final fileSize = await file.length();

      if (fileSize == null || fileSize == 0) {
        throw Exception('Unable to determine file size or the file is empty.');
      }

      if (fileSize > _maxDocumentSize) {
        throw Exception('File exceeds the maximum allowed size of 10 MB.');
      }

      // Verify that the selected file can be read.
      final fileBytes = await file.readAsBytes();

      if (fileBytes.isEmpty) {
        throw Exception('The selected file is empty or unreadable.');
      }

      if (fileBytes.length > _maxDocumentSize) {
        throw Exception('File exceeds the maximum allowed size of 10 MB.');
      }

      if (!mounted) return;

      _markFormChanged();
      setState(() {
        switch (documentType) {
          case 'IDENTIFICATION':
            _identificationDocument = file;
            break;

          case 'PROOF_OF_NEED':
            _proofOfNeedDocument = file;
            break;

          case 'COMPANY_REGISTRATION':
            _companyRegistrationDocument = file;
            break;

          default:
            throw ArgumentError('Unsupported document type: $documentType');
        }
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document selection failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _mimeForFile(PlatformFile file) {
    switch (file.extension?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        throw const FormatException('Unsupported document type.');
    }
  }

  Future<void> _attachFile(
    http.MultipartRequest request,
    String field,
    PlatformFile file,
  ) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > _maxDocumentSize) {
      throw FormatException('Invalid file size for ${file.name}.');
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: file.name,
        contentType: MediaType.parse(_mimeForFile(file)),
      ),
    );
  }

  Future<void> _submitRequest() async {
    if (_submitting || _submittedReference != null) return;
    if (!_formKey.currentState!.validate()) return;

    final petrolText = _petrolLitresController.text.trim();
    final dieselText = _dieselLitresController.text.trim();
    final decimalPattern = RegExp(r'^\d+(?:\.\d{1,2})?$');
    bool validQuantity(String text) =>
        text.isEmpty || decimalPattern.hasMatch(text);
    final petrol = double.tryParse(petrolText.isEmpty ? '0' : petrolText);
    final diesel = double.tryParse(dieselText.isEmpty ? '0' : dieselText);

    if (!validQuantity(petrolText) ||
        !validQuantity(dieselText) ||
        petrol == null ||
        diesel == null ||
        !petrol.isFinite ||
        !diesel.isFinite ||
        petrol < 0 ||
        diesel < 0 ||
        petrol + diesel <= 0 ||
        petrol > 999999999999.99 ||
        diesel > 999999999999.99) {
      _showError(
        'Enter a valid positive quantity of Petrol or Diesel (up to two decimal places).',
      );
      return;
    }
    if (_selectedDistrictId == null ||
        _selectedOmcId == null ||
        _selectedStationId == null) {
      _showError('Select the district, OMC and filling station.');
      return;
    }
    if (_identificationDocument == null || _proofOfNeedDocument == null) {
      _showError('Identification and Proof of Fuel Requirement are required.');
      return;
    }

    final items = <Map<String, dynamic>>[];
    if (petrol > 0) items.add({'product': 'PETROL', 'litres': petrol});
    if (diesel > 0) items.add({'product': 'DIESEL', 'litres': diesel});

    final payload = <String, dynamic>{
      'applicant_name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'district_id': _selectedDistrictId,
      'omc_id': _selectedOmcId,
      'station_id': _selectedStationId,
      'reason': _reasonController.text.trim(),
      'items': items,
    };

    _submissionId ??= const Uuid().v4();
    setState(() => _submitting = true);

    try {
      final endpoint = Uri.parse(
        'https://sccwkrquytcawzaqduil.supabase.co/functions/v1/submit-once-off-fuel-request',
      );

      final request = http.MultipartRequest('POST', endpoint)
        ..headers['apikey'] = 'sb_publishable_lJTu9Xl5EbhCFh0GDCwOVA_rPwy3j6F'
        ..fields['request'] = jsonEncode(payload)
        ..fields['submission_id'] = _submissionId!;

      await _attachFile(request, 'identification', _identificationDocument!);

      await _attachFile(request, 'proof_of_need', _proofOfNeedDocument!);

      if (_companyRegistrationDocument != null) {
        await _attachFile(
          request,
          'company_registration',
          _companyRegistrationDocument!,
        );
      }

      final client = http.Client();
      late http.Response response;
      try {
        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 120));
        response = await http.Response.fromStream(streamed);
      } finally {
        client.close();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected server response.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['success'] != true) {
        throw Exception(
          decoded['error']?.toString() ??
              'Submission failed (HTTP ${response.statusCode}).',
        );
      }
      final reference = decoded['request_number']?.toString();
      if (reference == null || reference.isEmpty) {
        throw const FormatException(
          'The server did not return a reference number.',
        );
      }
      if (!mounted) return;
      setState(() => _submittedReference = reference);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request submitted: $reference'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(
        'Unable to confirm submission: $error. Retry without changing the form.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _reasonController.dispose();
    _petrolLitresController.dispose();
    _dieselLitresController.dispose();
    super.dispose();
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'This field is required';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MeraColors.background,
      appBar: AppBar(title: const Text('Once-Off Fuel Request')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AbsorbPointer(
                    absorbing: _submitting,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset('assets/images/mera_logo.png', height: 85),
                        const SizedBox(height: 20),
                        const Text(
                          'Once-Off Container Fuel Request',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: MeraColors.darkGreen,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Complete the information below to '
                          'request container fuel approval.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),

                        _buildTextField(
                          label: 'Full Name',
                          controller: _nameController,
                        ),
                        _buildTextField(
                          label: 'Phone Number',
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                        ),
                        _buildTextField(
                          label: 'Email Address',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        _buildTextField(
                          label: 'Reason for Requesting Fuel',
                          controller: _reasonController,
                          maxLines: 4,
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          'Fuel Collection Location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: MeraColors.darkGreen,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // DISTRICT
                        DropdownButtonFormField<String>(
                          key: ValueKey('district-$_selectedDistrictId'),
                          initialValue: _selectedDistrictId,
                          decoration: InputDecoration(
                            labelText: 'District',
                            border: const OutlineInputBorder(),
                            suffixIcon: _loadingDistricts
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                          ),
                          isExpanded: true,
                          items: _districts.map((district) {
                            return DropdownMenuItem<String>(
                              value: district['id'].toString(),
                              child: Text(district['name'].toString()),
                            );
                          }).toList(),
                          onChanged: _loadingDistricts ? null : _selectDistrict,
                          validator: (value) =>
                              value == null ? 'Please select a district' : null,
                        ),

                        const SizedBox(height: 16),

                        // OMC
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'omc-$_selectedDistrictId-$_selectedOmcId',
                          ),
                          initialValue: _selectedOmcId,
                          decoration: InputDecoration(
                            labelText: 'Oil Marketing Company (OMC)',
                            border: const OutlineInputBorder(),
                            suffixIcon: _loadingOmcs
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                          ),
                          isExpanded: true,
                          items: _omcs.map((omc) {
                            return DropdownMenuItem<String>(
                              value: omc['id'].toString(),
                              child: Text(omc['name'].toString()),
                            );
                          }).toList(),
                          onChanged: _selectedDistrictId == null || _loadingOmcs
                              ? null
                              : _selectOmc,
                          validator: (value) =>
                              value == null ? 'Please select an OMC' : null,
                        ),

                        const SizedBox(height: 16),

                        // FILLING STATION
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'station-$_selectedDistrictId-$_selectedOmcId',
                          ),
                          initialValue: _selectedStationId,
                          decoration: InputDecoration(
                            labelText: 'Filling Station',
                            border: const OutlineInputBorder(),
                            suffixIcon: _loadingStations
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                          ),
                          isExpanded: true,
                          items: _stations.map((station) {
                            return DropdownMenuItem<String>(
                              value: station['station_id'].toString(),
                              child: Text(station['station_name'].toString()),
                            );
                          }).toList(),
                          onChanged: _selectedOmcId == null || _loadingStations
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedStationId = value;
                                    _markFormChanged();
                                  });
                                },
                          validator: (value) => value == null
                              ? 'Please select a filling station'
                              : null,
                        ),

                        if (_locationError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _locationError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // FUEL QUANTITY SECTION
                        const Divider(height: 32),

                        const Text(
                          'Fuel Requirements',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Enter the quantity of fuel required in litres. '
                          'You may request Petrol, Diesel, or both.',
                        ),

                        const SizedBox(height: 20),

                        TextFormField(
                          controller: _petrolLitresController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Petrol Quantity (Litres)',
                            hintText: 'e.g. 100',
                            prefixIcon: Icon(Icons.local_gas_station),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _dieselLitresController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Diesel Quantity (Litres)',
                            hintText: 'e.g. 200',
                            prefixIcon: Icon(Icons.local_gas_station),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // DOCUMENT UPLOAD SECTION
                        const Divider(height: 32),

                        const Text(
                          'Supporting Documents',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Upload PDF, JPG, PNG or WebP documents. '
                          'Maximum file size: 10 MB per document.',
                        ),

                        const SizedBox(height: 20),

                        // IDENTIFICATION DOCUMENT - REQUIRED
                        const Text(
                          'Identification Document *',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),

                        const SizedBox(height: 8),

                        OutlinedButton.icon(
                          onPressed: () => _pickDocument('IDENTIFICATION'),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose Identification Document'),
                        ),

                        if (_identificationDocument != null)
                          Text(
                            'Selected: ${_identificationDocument!.name}',
                            style: const TextStyle(color: Colors.green),
                          ),

                        const SizedBox(height: 20),

                        // PROOF OF FUEL REQUIREMENT - REQUIRED
                        const Text(
                          'Proof of Fuel Requirement *',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),

                        const SizedBox(height: 8),

                        OutlinedButton.icon(
                          onPressed: () => _pickDocument('PROOF_OF_NEED'),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose Proof of Fuel Requirement'),
                        ),

                        if (_proofOfNeedDocument != null)
                          Text(
                            'Selected: ${_proofOfNeedDocument!.name}',
                            style: const TextStyle(color: Colors.green),
                          ),

                        const SizedBox(height: 20),

                        // COMPANY REGISTRATION - OPTIONAL
                        const Text(
                          'Company Registration Certificate (Optional)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),

                        const SizedBox(height: 8),

                        OutlinedButton.icon(
                          onPressed: () =>
                              _pickDocument('COMPANY_REGISTRATION'),
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                            'Choose Company Registration Certificate',
                          ),
                        ),

                        if (_companyRegistrationDocument != null)
                          Text(
                            'Selected: ${_companyRegistrationDocument!.name}',
                            style: const TextStyle(color: Colors.green),
                          ),

                        const SizedBox(height: 24),
                        const SizedBox(height: 10),
                        if (_submittedReference != null) ...[
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 44,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Request submitted successfully',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            'MERA Reference: $_submittedReference',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please keep this reference number. Your request is awaiting MERA review.',
                            textAlign: TextAlign.center,
                          ),
                        ] else
                          FilledButton(
                            onPressed: _submitting ? null : _submitRequest,
                            style: FilledButton.styleFrom(
                              backgroundColor: MeraColors.green,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _submitting
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text('SUBMITTING REQUEST...'),
                                      ],
                                    )
                                  : const Text('SUBMIT REQUEST'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
