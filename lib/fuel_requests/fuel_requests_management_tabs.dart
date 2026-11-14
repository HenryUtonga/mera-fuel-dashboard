import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _show(dynamic v) =>
    v == null || v.toString().trim().isEmpty ? '—' : v.toString();

void _notice(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// Wait for the dialog exit animation and widget teardown before disposing
// TextEditingControllers or rebuilding the parent dialog.
Future<T?> _showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
  );
  final result = await Navigator.of(context, rootNavigator: true).push<T>(route);
  await route.completed;
  return result;
}

class FuelOmcsAdminTab extends StatefulWidget {
  const FuelOmcsAdminTab({super.key});
  @override
  State<FuelOmcsAdminTab> createState() => FuelOmcsAdminTabState();
}

class FuelOmcsAdminTabState extends State<FuelOmcsAdminTab> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _omcs = [];
  Map<String, List<Map<String, dynamic>>> _contactsByOmc = {};
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.rpc('list_fuel_request_omcs_admin');
      final omcs = List<Map<String, dynamic>>.from(rows);
      final contacts = <String, List<Map<String, dynamic>>>{};
      // Fetch through the admin-only RPC; never query private contacts directly.
      final results = await Future.wait(
        omcs.map((omc) async {
          final id = omc['id'].toString();
          final data = await _db.rpc(
            'list_fuel_request_omc_contacts',
            params: {'p_omc_id': omc['id']},
          );
          return MapEntry(id, List<Map<String, dynamic>>.from(data));
        }),
      );
      for (final result in results) {
        contacts[result.key] = result.value;
      }
      if (mounted) {
        setState(() {
          _omcs = omcs;
          _contactsByOmc = contacts;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editOmc([Map<String, dynamic>? omc]) async {
    final name = TextEditingController(text: omc?['name']?.toString() ?? '');
    bool active = omc?['active'] != false;
    final saved = await _showSettledDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(omc == null ? 'Add OMC' : 'Edit OMC'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'OMC name'),
                ),
                SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => update(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  _notice(context, 'OMC name is required');
                  return;
                }
                try {
                  await _db.rpc(
                    'manage_fuel_request_omc',
                    params: {
                      'p_omc_id': omc?['id'],
                      'p_name': name.text.trim(),
                      'p_active': active,
                    },
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) _notice(context, 'Save failed: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (saved == true) await refresh();
  }

  Future<void> _contacts(Map<String, dynamic> omc) async {
    await _showSettledDialog<void>(
      context: context,
      builder: (_) => _OmcContactsDialog(omc: omc),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'OMC Management',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            FilledButton.icon(
              onPressed: () => _editOmc(),
              icon: const Icon(Icons.add),
              label: const Text('Add OMC'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) SelectableText('Unable to load OMCs: $_error'),
        if (!_loading && _error == null)
          Expanded(
            child: _omcs.isEmpty
                ? const Center(child: Text('No OMCs found'))
                : ListView.builder(
                    itemCount: _omcs.length,
                    itemBuilder: (context, index) {
                      final omc = _omcs[index];
                      final contacts =
                          _contactsByOmc[omc['id'].toString()] ?? [];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _show(omc['name']),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      omc['active'] == true
                                          ? 'Active'
                                          : 'Inactive',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _editOmc(omc),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Edit OMC'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _contacts(omc),
                                    icon: const Icon(
                                      Icons.contact_mail_outlined,
                                    ),
                                    label: const Text('Manage contacts'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (contacts.isEmpty)
                                const Text(
                                  'Contact person: Not configured  •  Email: —  •  Phone: —',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else
                                for (final c in contacts)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Contact: ${_show(c['contact_name'])}',
                                        ),
                                        Text(
                                          'Designation: ${_show(c['designation'])}',
                                        ),
                                        Text('Email: ${_show(c['email'])}'),
                                        Text(
                                          'Phone: ${_show(c['phone_number'])}',
                                        ),
                                        Text(
                                          'Notifications: ${c['receive_notifications'] == true && c['active'] == true ? 'Enabled' : 'Disabled'}',
                                        ),
                                        Text(
                                          'Contact: ${c['active'] == true ? 'Active' : 'Inactive'}',
                                        ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    ),
  );
}

class _OmcContactsDialog extends StatefulWidget {
  final Map<String, dynamic> omc;
  const _OmcContactsDialog({required this.omc});
  @override
  State<_OmcContactsDialog> createState() => _OmcContactsDialogState();
}

class _OmcContactsDialogState extends State<_OmcContactsDialog> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _contacts = [];
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
      final rows = await _db.rpc(
        'list_fuel_request_omc_contacts',
        params: {'p_omc_id': widget.omc['id']},
      );
      if (mounted) {
        setState(() => _contacts = List<Map<String, dynamic>>.from(rows));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? contact]) async {
    final name = TextEditingController(
      text: contact?['contact_name']?.toString() ?? '',
    );
    final designation = TextEditingController(
      text: contact?['designation']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: contact?['phone_number']?.toString() ?? '',
    );
    final email = TextEditingController(
      text: contact?['email']?.toString() ?? '',
    );
    bool active = contact?['active'] != false;
    bool notify = contact?['receive_notifications'] != false;
    final saved = await _showSettledDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(contact == null ? 'Add OMC contact' : 'Edit OMC contact'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Contact name *',
                    ),
                  ),
                  TextField(
                    controller: designation,
                    decoration: const InputDecoration(labelText: 'Designation'),
                  ),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  SwitchListTile(
                    title: const Text('Receive notifications'),
                    value: notify,
                    onChanged: (v) => update(() => notify = v),
                  ),
                  SwitchListTile(
                    title: const Text('Active'),
                    value: active,
                    onChanged: (v) => update(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty ||
                    (phone.text.trim().isEmpty && email.text.trim().isEmpty) ||
                    (notify && email.text.trim().isEmpty)) {
                  _notice(
                    context,
                    'Name and a contact method are required; notification recipients also need an email.',
                  );
                  return;
                }
                try {
                  await _db.rpc(
                    'manage_fuel_request_omc_contact',
                    params: {
                      'p_contact_id': contact?['id'],
                      'p_omc_id': widget.omc['id'],
                      'p_contact_name': name.text.trim(),
                      'p_designation': designation.text.trim().isEmpty
                          ? null
                          : designation.text.trim(),
                      'p_phone_number': phone.text.trim().isEmpty
                          ? null
                          : phone.text.trim(),
                      'p_email': email.text.trim().isEmpty
                          ? null
                          : email.text.trim(),
                      'p_receive_notifications': notify,
                      'p_active': active,
                    },
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) _notice(context, 'Save failed: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    designation.dispose();
    phone.dispose();
    email.dispose();
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Contacts — ${_show(widget.omc['name'])}'),
    content: SizedBox(
      width: 680,
      height: 440,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add contact'),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText('Unable to load contacts: $_error'),
          if (!_loading && _error == null)
            Expanded(
              child: _contacts.isEmpty
                  ? const Center(child: Text('No contacts yet'))
                  : ListView.builder(
                      itemCount: _contacts.length,
                      itemBuilder: (context, index) {
                        final c = _contacts[index];
                        return ListTile(
                          title: Text(_show(c['contact_name'])),
                          subtitle: Text(
                            '${_show(c['designation'])} • ${_show(c['email'])} • ${_show(c['phone_number'])}\n${c['active'] == true ? 'Active' : 'Inactive'} • Notifications: ${c['receive_notifications'] == true ? 'Yes' : 'No'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Edit contact',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _edit(c),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class FuelRegionalApproversTab extends StatefulWidget {
  const FuelRegionalApproversTab({super.key});
  @override
  State<FuelRegionalApproversTab> createState() =>
      FuelRegionalApproversTabState();
}

class FuelRegionalApproversTabState extends State<FuelRegionalApproversTab> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  static const _regions = ['CENTRAL', 'NORTHERN', 'SOUTHERN'];
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.rpc('list_fuel_regional_approvers_admin');
      if (mounted) {
        setState(() => _rows = List<Map<String, dynamic>>.from(rows));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manage(Map<String, dynamic> staff) async {
    final staffId = staff['staff_id'];
    final assignments = _rows.where((r) => r['staff_id'] == staffId).toList();
    final enabled = {
      for (final region in _regions)
        region: assignments.any(
          (r) => r['region_name'] == region && r['assignment_active'] == true,
        ),
    };
    bool approver = staff['approver_permission_active'] == true;
    bool viewer = staff['viewer_permission_active'] == true;
    bool saving = false;
    final changed = await _showSettledDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Regional access — ${_show(staff['staff_name'])}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (staff['staff_active'] != true)
                  const Text('Inactive staff: changes are not permitted.'),
                for (final region in _regions)
                  CheckboxListTile(
                    title: Text('$region region'),
                    value: enabled[region] ?? false,
                    onChanged: saving || staff['staff_active'] != true
                        ? null
                        : (v) => update(() => enabled[region] = v ?? false),
                  ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Fuel Request Approver permission'),
                  value: approver,
                  onChanged: saving || staff['staff_active'] != true
                      ? null
                      : (v) => update(() => approver = v),
                ),
                SwitchListTile(
                  title: const Text('Fuel Request Viewer permission'),
                  value: viewer,
                  onChanged: saving || staff['staff_active'] != true
                      ? null
                      : (v) => update(() => viewer = v),
                ),
                const Text(
                  'Region membership and approval permission are separate. Changes are saved individually.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving || staff['staff_active'] != true
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        final originalRegions = {
                          for (final region in _regions)
                            region: assignments.any(
                              (r) =>
                                  r['region_name'] == region &&
                                  r['assignment_active'] == true,
                            ),
                        };
                        for (final region in _regions) {
                          if (originalRegions[region] != enabled[region]) {
                            await _db.rpc(
                              'manage_fuel_region_approver',
                              params: {
                                'p_staff_id': staffId,
                                'p_region_name': region,
                                'p_enable': enabled[region],
                              },
                            );
                          }
                        }
                        if (approver !=
                            (staff['approver_permission_active'] == true)) {
                          await _db.rpc(
                            'manage_fuel_staff_permission',
                            params: {
                              'p_staff_id': staffId,
                              'p_permission': 'FUEL_REQUEST_APPROVER',
                              'p_enable': approver,
                            },
                          );
                        }
                        if (viewer !=
                            (staff['viewer_permission_active'] == true)) {
                          await _db.rpc(
                            'manage_fuel_staff_permission',
                            params: {
                              'p_staff_id': staffId,
                              'p_permission': 'FUEL_REQUEST_VIEWER',
                              'p_enable': viewer,
                            },
                          );
                        }
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) {
                          _notice(
                            context,
                            'Change failed; some earlier changes may have saved. Refresh to verify: $e',
                          );
                        }
                        update(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    if (changed == true) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final staff = <String, Map<String, dynamic>>{};
    for (final row in _rows) {
      staff.putIfAbsent(row['staff_id'].toString(), () => row);
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Regional Approvers',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Approval regions: CENTRAL (9 districts), NORTHERN (6), SOUTHERN (13). Assignments and permissions are managed separately.',
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText('Unable to load regional approvers: $_error'),
          if (!_loading && _error == null)
            Expanded(
              child: staff.isEmpty
                  ? const Center(child: Text('No staff records found'))
                  : ListView(
                      children: staff.values.map((person) {
                        final assignments = _rows
                            .where(
                              (r) =>
                                  r['staff_id'] == person['staff_id'] &&
                                  r['assignment_active'] == true,
                            )
                            .map((r) => r['region_name'].toString())
                            .toList();
                        return Card(
                          child: ListTile(
                            title: Text(
                              '${_show(person['staff_name'])} (${_show(person['staff_number'])})',
                            ),
                            subtitle: Text(
                              'Regions: ${assignments.isEmpty ? 'None' : assignments.join(', ')}\nAccount: ${person['staff_active'] == true ? 'Active' : 'Inactive'} • Approver: ${person['approver_permission_active'] == true ? 'Yes' : 'No'} • Viewer: ${person['viewer_permission_active'] == true ? 'Yes' : 'No'}',
                            ),
                            isThreeLine: true,
                            trailing: OutlinedButton.icon(
                              onPressed: person['staff_active'] == true
                                  ? () => _manage(person)
                                  : null,
                              icon: const Icon(Icons.manage_accounts_outlined),
                              label: const Text('Manage'),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
        ],
      ),
    );
  }
}
