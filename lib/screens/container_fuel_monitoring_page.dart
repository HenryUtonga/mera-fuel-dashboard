import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-page MERA Container Fuel Monitoring dashboard.
/// Data comes from dashboard_container_fuel_report_v2 (authorized server-side).
class ContainerFuelMonitoringPage extends StatefulWidget {
  const ContainerFuelMonitoringPage({super.key});

  @override
  State<ContainerFuelMonitoringPage> createState() =>
      _ContainerFuelMonitoringPageState();
}

class _ContainerFuelMonitoringPageState
    extends State<ContainerFuelMonitoringPage> {
  String _period = 'This Month';
  String _trendGranularity = 'Daily';
  String _product = 'All products';
  String _search = '';
  String? _selectedCustomerKey;
  String? _selectedGeographyType;
  String? _selectedGeographyName;
  String? _selectedExceptionCustomerKey;
  String? _selectedAllowanceApplicantId;
  DateTimeRange? _customRange;
  late Future<Map<String, dynamic>> _report;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DateTime _malawiNow() => DateTime.now().toUtc().add(const Duration(hours: 2));
  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTimeRange? _range() {
    final n = _malawiNow();
    final today = DateTime(n.year, n.month, n.day);
    switch (_period) {
      case 'Today':
        return DateTimeRange(start: today, end: today);
      case 'Yesterday':
        final d = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: d, end: d);
      case 'This Week':
        return DateTimeRange(
          start: today.subtract(Duration(days: today.weekday - 1)),
          end: today,
        );
      case 'This Month':
        return DateTimeRange(
          start: DateTime(today.year, today.month),
          end: today,
        );
      case 'Custom Range':
        return _customRange;
      default:
        return null;
    }
  }

  void _reload() => _report = _fetch();

  Future<Map<String, dynamic>> _fetch() async {
    final range = _range();
    if (_period == 'Custom Range' && range == null) return {};
    final result = await Supabase.instance.client.rpc(
      'dashboard_container_fuel_report_v2',
      params: {
        'p_start_date': range == null ? null : _date(range.start),
        'p_end_date': range == null ? null : _date(range.end),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw const FormatException('Unexpected container fuel report response');
  }

  Future<void> _choosePeriod(String value) async {
    if (value == 'Custom Range') {
      final n = _malawiNow();
      final chosen = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(n.year + 1, 12, 31),
        initialDateRange: _customRange,
      );
      if (!mounted || chosen == null) return;
      setState(() {
        _customRange = chosen;
        _period = value;
        _reload();
      });
    } else {
      setState(() {
        _period = value;
        _reload();
      });
    }
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _rows(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _str(dynamic v) => v == null || '$v'.trim().isEmpty ? '—' : '$v';
  String _qty(dynamic v) {
    final n = _num(v);
    final s = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2).split('.');
    final head = s[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return s.length == 1 ? head : '$head.${s[1]}';
  }

  String _timestamp(dynamic v) {
    if (v == null) return '—';
    final d = DateTime.tryParse('$v');
    if (d == null) return '$v';
    final local = d.toUtc().add(const Duration(hours: 2));
    return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _metric(String label, String value, IconData icon, {String? note}) =>
      SizedBox(
        width: 205,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 25,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 9),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _note(String s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Text(s, style: Theme.of(context).textTheme.bodySmall),
  );

  Widget _section(
    String title,
    IconData icon,
    Widget child, {
    bool initiallyExpanded = false,
  }) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      children: [Align(alignment: Alignment.centerLeft, child: child)],
    ),
  );

  Widget _table(List<String> headings, List<List<String>> data) {
    if (data.isEmpty) {
      return _note('No records for the selected period or filters.');
    }
    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: headings.map((h) => DataColumn(label: Text(h))).toList(),
          rows: data
              .map(
                (cells) => DataRow(
                  cells: cells.map((c) => DataCell(Text(c))).toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterRows(
    List<Map<String, dynamic>> rows, {
    bool applyProduct = true,
  }) {
    final term = _search.trim().toLowerCase();
    return rows.where((r) {
      if (applyProduct &&
          _product != 'All products' &&
          r.containsKey('product') &&
          '${r['product']}'.toUpperCase() != _product.toUpperCase()) {
        return false;
      }
      if (term.isEmpty) return true;
      return r.values.any((v) => '$v'.toLowerCase().contains(term));
    }).toList();
  }

  String _csvCell(dynamic v) {
    final s = (v ?? '').toString();
    final safe = RegExp(r'^\s*[=+@\-\t\r]').hasMatch(s) ? "'$s" : s;
    return '"${safe.replaceAll('"', '""')}"';
  }

  void _export(
    String filename,
    List<String> keys,
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records available to export.')),
      );
      return;
    }
    final b = StringBuffer()..writeln(keys.map(_csvCell).join(','));
    for (final r in rows) {
      b.writeln(keys.map((k) => _csvCell(r[k])).join(','));
    }
    final csv = '\uFEFF${b.toString()}';
    final uri = Uri.dataFromString(csv, mimeType: 'text/csv', encoding: utf8);
    final anchor = web.HTMLAnchorElement()
      ..href = uri.toString()
      ..download = filename;
    anchor.click();
  }

  Widget _trendChart(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _note('No trend dates returned.');
    final data = rows
        .map(
          (r) => _TrendPoint(
            _str(
              r[_trendGranularity == 'Weekly'
                  ? 'week_start'
                  : _trendGranularity == 'Monthly'
                  ? 'month_start'
                  : 'date'],
            ),
            _num(r['petrol_litres']),
            _num(r['diesel_litres']),
          ),
        )
        .toList();
    final w = math.max(650.0, data.length * 52.0 + 95.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Group by:'),
            for (final type in const ['Daily', 'Weekly', 'Monthly'])
              ChoiceChip(
                label: Text(type),
                selected: _trendGranularity == type,
                onSelected: (_) => setState(() => _trendGranularity = type),
              ),
            const SizedBox(width: 8),
            const _Legend(color: Colors.teal, label: 'Petrol'),
            const _Legend(color: Colors.blue, label: 'Diesel'),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: w,
            height: 285,
            child: _TrendPlot(points: data, product: _product),
          ),
        ),
        _note(
          'Confirmed fuel by Malawi calendar date. Zero-consumption periods are included. '
          'Daily shows individual days; Weekly and Monthly show aggregated periods. '
          'Scroll horizontally to view longer periods.',
        ),
      ],
    );
  }

  Widget _overview(Map<String, dynamic> s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _metric(
            'Petrol confirmed',
            '${_qty(s['petrol_litres'])} L',
            Icons.local_gas_station,
          ),
          _metric(
            'Diesel confirmed',
            '${_qty(s['diesel_litres'])} L',
            Icons.local_gas_station,
          ),
          _metric(
            'Total confirmed',
            '${_qty(s['total_litres'])} L',
            Icons.water_drop_outlined,
          ),
          _metric(
            'Confirmed allocations',
            _qty(s['confirmed_allocations']),
            Icons.check_circle_outline,
          ),
          _metric(
            'Customer identifiers',
            _qty(s['unique_customers']),
            Icons.people_outline,
          ),
          _metric(
            'Stations used',
            _qty(s['stations_used']),
            Icons.store_outlined,
          ),
          _metric('OMCs used', _qty(s['omcs_used']), Icons.business_outlined),
          _metric(
            'Districts used',
            _qty(s['districts_used']),
            Icons.map_outlined,
          ),
          _metric(
            'Registered customers',
            _qty(s['registered_customers']),
            Icons.badge_outlined,
          ),
          _metric(
            'One-off requests confirmed',
            _qty(s['one_off_requests_confirmed']),
            Icons.assignment_outlined,
          ),
        ],
      ),
      _note(
        'Consumption means the latest CONFIRMED station outcome on a COMPLETED allocation. '
        'Unregistered requests are counted as separate identifiers, not verified distinct people. '
        'Allocations are not necessarily physical visits.',
      ),
    ],
  );

  Widget _customerSection(Map<String, dynamic> report) {
    final customers = _filterRows(
      _rows(report['customers']),
      applyProduct: false,
    );
    final allHistory = _rows(report['history']);
    final selectedMatches = _selectedCustomerKey == null
        ? <Map<String, dynamic>>[]
        : allHistory
              .where(
                (r) => r['customer_key']?.toString() == _selectedCustomerKey,
              )
              .toList();
    final selectedCustomer = _selectedCustomerKey == null
        ? <String, dynamic>{}
        : _rows(report['customers']).firstWhere(
            (r) => r['customer_key']?.toString() == _selectedCustomerKey,
            orElse: () => <String, dynamic>{},
          );
    final history = _selectedCustomerKey == null
        ? _filterRows(allHistory)
        : selectedMatches
              .where(
                (r) =>
                    _product == 'All products' ||
                    r['product']?.toString().toUpperCase() == _product,
              )
              .toList();
    final selected = _selectedCustomerKey != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer consumption rankings',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        _note(
          'Select a customer row to display their confirmed fueling history below. '
          'Select the same row again to return to all customers.',
        ),
        if (customers.isEmpty)
          _note('No customers for the selected period or search.')
        else
          Card(
            elevation: 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Company')),
                  DataColumn(label: Text('Petrol (L)')),
                  DataColumn(label: Text('Diesel (L)')),
                  DataColumn(label: Text('Total (L)')),
                  DataColumn(label: Text('Confirmed allocations')),
                  DataColumn(label: Text('Stations')),
                ],
                rows: customers.map((r) {
                  final key = r['customer_key']?.toString();
                  final isSelected = key != null && key == _selectedCustomerKey;
                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: key == null
                        ? null
                        : (_) {
                            setState(() {
                              _selectedCustomerKey = isSelected ? null : key;
                            });
                          },
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 17,
                                  color: Colors.green,
                                ),
                              ),
                            Text(_str(r['customer'])),
                          ],
                        ),
                      ),
                      DataCell(Text(_str(r['company']))),
                      DataCell(Text(_qty(r['petrol_litres']))),
                      DataCell(Text(_qty(r['diesel_litres']))),
                      DataCell(Text(_qty(r['total_litres']))),
                      DataCell(Text(_qty(r['confirmed_allocations']))),
                      DataCell(Text(_qty(r['stations_visited']))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (selected) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_str(selectedCustomer['customer'])} — Fueling History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedCustomerKey = null),
                icon: const Icon(Icons.close),
                label: const Text('Show all customers'),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _metric(
                'Petrol confirmed',
                '${_qty(selectedCustomer['petrol_litres'])} L',
                Icons.local_gas_station_outlined,
              ),
              _metric(
                'Diesel confirmed',
                '${_qty(selectedCustomer['diesel_litres'])} L',
                Icons.water_drop_outlined,
              ),
              _metric(
                'Total confirmed',
                '${_qty(selectedCustomer['total_litres'])} L',
                Icons.check_circle_outline,
              ),
              _metric(
                'Confirmed allocations',
                _qty(selectedCustomer['confirmed_allocations']),
                Icons.receipt_long_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: selectedMatches.isEmpty
                ? null
                : () => _export(
                    'mera_customer_fueling_${_date(_malawiNow())}.csv',
                    const [
                      'request_number',
                      'customer',
                      'company',
                      'product',
                      'litres',
                      'allocated_litres',
                      'confirmed_at',
                      'date',
                      'station',
                      'omc',
                      'district',
                    ],
                    selectedMatches,
                  ),
            icon: const Icon(Icons.download),
            label: const Text('Export this customer’s history (CSV)'),
          ),
          const SizedBox(height: 8),
        ] else
          Text(
            'Confirmed fueling history — all customers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        _table(
          const [
            'Confirmed (Malawi)',
            'Request',
            'Customer',
            'Product',
            'Confirmed (L)',
            'Allocated (L)',
            'Station',
            'OMC',
            'District',
          ],
          history
              .map(
                (r) => [
                  _timestamp(r['confirmed_at']),
                  _str(r['request_number']),
                  _str(r['customer']),
                  _str(r['product']),
                  _qty(r['litres']),
                  _qty(r['allocated_litres']),
                  _str(r['station']),
                  _str(r['omc']),
                  _str(r['district']),
                ],
              )
              .toList(),
        ),
        _note(
          selected
              ? 'The customer totals cover both products for the selected reporting period. '
                    'The product filter affects the history table; the customer CSV contains both products. '
                    'One-off identities are linked by request, not by name alone.'
              : 'Select a customer above to see their history on this page. '
                    'The product filter applies to the history table; rankings include both products.',
        ),
      ],
    );
  }

  Widget _geographySection(Map<String, dynamic> report) {
    final stations = _filterRows(_rows(report['stations']), applyProduct: false)
      ..sort(
        (a, b) => _num(b['total_litres']).compareTo(_num(a['total_litres'])),
      );
    final omcs = _filterRows(_rows(report['omcs']), applyProduct: false)
      ..sort(
        (a, b) => _num(b['total_litres']).compareTo(_num(a['total_litres'])),
      );
    final districts =
        _filterRows(_rows(report['districts']), applyProduct: false)..sort(
          (a, b) => _num(b['total_litres']).compareTo(_num(a['total_litres'])),
        );
    final history = _rows(report['history']);
    final type = _selectedGeographyType;
    final name = _selectedGeographyName;
    final matchedHistory = type == null || name == null
        ? <Map<String, dynamic>>[]
        : history.where((r) {
            final field = type == 'Station'
                ? 'station'
                : type == 'OMC'
                ? 'omc'
                : 'district';
            return r[field]?.toString() == name;
          }).toList();
    final selectedHistory = _filterRows(matchedHistory);
    final relatedStations = type == null || name == null
        ? <Map<String, dynamic>>[]
        : stations.where((r) {
            if (type == 'Station') return r['station']?.toString() == name;
            if (type == 'OMC') return r['omc']?.toString() == name;
            return r['district']?.toString() == name;
          }).toList();
    double sum(String product) => matchedHistory
        .where((r) => r['product']?.toString().toUpperCase() == product)
        .fold<double>(0, (total, r) => total + _num(r['litres']));
    Widget ranking(
      String title,
      List<Map<String, dynamic>> rows,
      String key,
      String rowType,
      List<String> headings,
      List<String> fields,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            _note('No records for the selected period or search.')
          else
            Card(
              elevation: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: headings
                      .map((h) => DataColumn(label: Text(h)))
                      .toList(),
                  rows: rows.map((r) {
                    final rowName = r[key]?.toString() ?? '';
                    final selected = type == rowType && name == rowName;
                    return DataRow(
                      selected: selected,
                      onSelectChanged: (_) => setState(() {
                        if (selected) {
                          _selectedGeographyType = null;
                          _selectedGeographyName = null;
                        } else {
                          _selectedGeographyType = rowType;
                          _selectedGeographyName = rowName;
                        }
                      }),
                      cells: fields
                          .map(
                            (f) => DataCell(
                              Text(
                                f == key ||
                                        f == 'omc' ||
                                        f == 'district' ||
                                        f == 'station'
                                    ? _str(r[f])
                                    : _qty(r[f]),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 14),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _note(
          'Select a station, OMC or district to view its confirmed fueling records '
          'directly below the rankings. Select the same row again to clear the selection. '
          'Rankings are ordered by total confirmed litres.',
        ),
        ranking(
          'Filling stations',
          stations,
          'station',
          'Station',
          const [
            'Station',
            'OMC',
            'District',
            'Petrol (L)',
            'Diesel (L)',
            'Total (L)',
            'Allocations',
          ],
          const [
            'station',
            'omc',
            'district',
            'petrol_litres',
            'diesel_litres',
            'total_litres',
            'confirmed_allocations',
          ],
        ),
        ranking(
          'Oil marketing companies (OMCs)',
          omcs,
          'omc',
          'OMC',
          const [
            'OMC',
            'Petrol (L)',
            'Diesel (L)',
            'Total (L)',
            'Stations',
            'Allocations',
          ],
          const [
            'omc',
            'petrol_litres',
            'diesel_litres',
            'total_litres',
            'stations_used',
            'confirmed_allocations',
          ],
        ),
        ranking(
          'Districts',
          districts,
          'district',
          'District',
          const [
            'District',
            'Petrol (L)',
            'Diesel (L)',
            'Total (L)',
            'Stations',
            'Allocations',
          ],
          const [
            'district',
            'petrol_litres',
            'diesel_litres',
            'total_litres',
            'stations_used',
            'confirmed_allocations',
          ],
        ),
        if (type != null && name != null) ...[
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$type: $name — Confirmed Fueling Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _selectedGeographyType = null;
                  _selectedGeographyName = null;
                }),
                icon: const Icon(Icons.close),
                label: const Text('Clear selection'),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _metric(
                'Petrol confirmed',
                '${_qty(sum('PETROL'))} L',
                Icons.local_gas_station_outlined,
              ),
              _metric(
                'Diesel confirmed',
                '${_qty(sum('DIESEL'))} L',
                Icons.water_drop_outlined,
              ),
              _metric(
                'Total confirmed',
                '${_qty(sum('PETROL') + sum('DIESEL'))} L',
                Icons.check_circle_outline,
              ),
              _metric(
                'Confirmed allocations',
                _qty(matchedHistory.length),
                Icons.receipt_long_outlined,
              ),
            ],
          ),
          if (type != 'Station') ...[
            const SizedBox(height: 12),
            Text(
              'Filling stations within $name',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _table(
              const [
                'Station',
                'OMC',
                'District',
                'Petrol (L)',
                'Diesel (L)',
                'Total (L)',
              ],
              relatedStations
                  .map(
                    (r) => [
                      _str(r['station']),
                      _str(r['omc']),
                      _str(r['district']),
                      _qty(r['petrol_litres']),
                      _qty(r['diesel_litres']),
                      _qty(r['total_litres']),
                    ],
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Confirmed fueling transactions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _table(
            const [
              'Confirmed (Malawi)',
              'Request',
              'Customer',
              'Product',
              'Litres',
              'Station',
              'OMC',
              'District',
            ],
            selectedHistory
                .map(
                  (r) => [
                    _timestamp(r['confirmed_at']),
                    _str(r['request_number']),
                    _str(r['customer']),
                    _str(r['product']),
                    _qty(r['litres']),
                    _str(r['station']),
                    _str(r['omc']),
                    _str(r['district']),
                  ],
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: matchedHistory.isEmpty
                ? null
                : () => _export(
                    'mera_geography_fueling_${_date(_malawiNow())}.csv',
                    const [
                      'request_number',
                      'customer',
                      'company',
                      'product',
                      'litres',
                      'confirmed_at',
                      'date',
                      'station',
                      'omc',
                      'district',
                    ],
                    matchedHistory,
                  ),
            icon: const Icon(Icons.download),
            label: Text('Export $type fueling history (CSV)'),
          ),
          _note(
            'The product filter affects the transaction table; the summary cards '
            'and CSV export cover both products. One confirmed allocation is not necessarily one physical visit.',
          ),
        ],
      ],
    );
  }

  Widget _funnelBar(
    String label,
    double litres,
    double maxLitres,
    Color color,
    String description,
  ) {
    final fraction = maxLitres > 0 ? (litres / maxLitres).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${_qty(litres)} L',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 16,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _requestsSection(Map<String, dynamic> report) {
    final rm = _map(report['request_metrics']);
    final litres = _map(report['requested_approved_litres']);
    final am = _map(report['allocation_metrics']);
    final cm = _map(report['confirmation_metrics']);
    final statuses = _map(report['request_statuses']);
    final summary = _map(report['summary']);
    final requested = _num(litres['total_requested_litres']);
    final approved = _num(litres['total_approved_litres']);
    final allocated = _num(am['total_allocated_litres']);
    final confirmed = _num(summary['total_litres']);
    final scale = math.max(
      1.0,
      math.max(math.max(requested, approved), math.max(allocated, confirmed)),
    );
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fuel request and dispensing overview',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric(
              'Requests received',
              _qty(rm['requests_received']),
              Icons.inbox_outlined,
            ),
            _metric(
              'Requests approved',
              _qty(rm['requests_approved']),
              Icons.task_alt,
            ),
            _metric(
              'Requests rejected',
              _qty(rm['requests_rejected']),
              Icons.block_outlined,
            ),
            _metric(
              'Litres requested',
              '${_qty(requested)} L',
              Icons.description_outlined,
            ),
            _metric(
              'Litres approved',
              '${_qty(approved)} L',
              Icons.assignment_turned_in_outlined,
            ),
            _metric(
              'Litres allocated',
              '${_qty(allocated)} L',
              Icons.local_shipping_outlined,
            ),
            _metric(
              'Recorded dispensed',
              '${_qty(am['total_recorded_dispensed_litres'])} L',
              Icons.opacity_outlined,
            ),
            _metric(
              'Confirmed consumption',
              '${_qty(confirmed)} L',
              Icons.check_circle_outline,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Fuel request funnel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _funnelBar(
                  'Requested',
                  requested,
                  scale,
                  colors.primary,
                  'Fuel requested on requests created in the selected period',
                ),
                _funnelBar(
                  'Approved',
                  approved,
                  scale,
                  Colors.teal,
                  'Approved item quantities for requests created in the selected period',
                ),
                _funnelBar(
                  'Allocated',
                  allocated,
                  scale,
                  Colors.blue,
                  'Allocations recorded in the selected period, including cancelled allocations',
                ),
                _funnelBar(
                  'Confirmed consumption',
                  confirmed,
                  scale,
                  Colors.green,
                  'Completed allocations confirmed by stations in the selected period',
                ),
                _note(
                  'Workflow comparison only: the four bars use different event dates and '
                  'do not represent a matched request cohort. Do not subtract the bars '
                  'to calculate outstanding fuel.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Product quantities',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _table(
          const [
            'Product',
            'Requested (L)',
            'Approved (L)',
            'Allocated (L)',
            'Confirmed (L)',
          ],
          [
            [
              'Petrol',
              _qty(litres['petrol_requested_litres']),
              _qty(litres['petrol_approved_litres']),
              _qty(am['petrol_allocated_litres']),
              _qty(summary['petrol_litres']),
            ],
            [
              'Diesel',
              _qty(litres['diesel_requested_litres']),
              _qty(litres['diesel_approved_litres']),
              _qty(am['diesel_allocated_litres']),
              _qty(summary['diesel_litres']),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Allocation status',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric(
              'Active',
              _qty(am['active_allocations']),
              Icons.pending_actions,
            ),
            _metric(
              'Completed',
              _qty(am['completed_allocations']),
              Icons.check_circle_outline,
            ),
            _metric(
              'Cancelled',
              _qty(am['cancelled_allocations']),
              Icons.cancel_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Station confirmation outcomes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric(
              'Confirmed',
              _qty(cm['confirmed']),
              Icons.verified_outlined,
            ),
            _metric('Pending', _qty(cm['pending']), Icons.hourglass_empty),
            _metric(
              'NOT_FUELED — review',
              _qty(cm['not_fueled']),
              Icons.report_outlined,
            ),
          ],
        ),
        _note(
          'NOT_FUELED is a station response for MERA review, not an automatic '
          'cancellation or reallocation. The existing report provides aggregate '
          'counts, not individual pending/NOT_FUELED case details.',
        ),
        const SizedBox(height: 16),
        Text(
          'Request statuses',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _table(
          const ['Status', 'Requests'],
          (statuses.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .map((e) => [e.key, _qty(e.value)])
              .toList(),
        ),
        _note(
          'Request statuses are based on request creation dates; allocation '
          'statuses use allocation dates, and confirmation outcomes use confirmation '
          'record dates. These figures must not be treated as one matched cohort.',
        ),
      ],
    );
  }

  Widget _exceptionsSection(Map<String, dynamic> report) {
    final repeats = _filterRows(_rows(report['repeats']), applyProduct: false);
    final allowances = _filterRows(_rows(report['monthly_allowances']));
    final allHistory = _rows(report['history']);
    final flagged = allowances
        .where((r) => r['potential_exceedance'] == true)
        .length;
    final cm = _map(report['confirmation_metrics']);
    final pending = _num(cm['pending']);
    final notFueled = _num(cm['not_fueled']);
    final selectedRepeat = _selectedExceptionCustomerKey;
    final repeatHistory = selectedRepeat == null
        ? <Map<String, dynamic>>[]
        : allHistory
              .where((r) => r['customer_key']?.toString() == selectedRepeat)
              .toList();
    final selectedApplicant = _selectedAllowanceApplicantId;
    final applicantHistory = selectedApplicant == null
        ? <Map<String, dynamic>>[]
        : allHistory
              .where((r) => r['applicant_id']?.toString() == selectedApplicant)
              .toList();

    Widget transactions(List<Map<String, dynamic>> rows) => _table(
      const [
        'Confirmed (Malawi)',
        'Request',
        'Customer',
        'Product',
        'Litres',
        'Station',
        'OMC',
        'District',
      ],
      rows
          .map(
            (r) => [
              _timestamp(r['confirmed_at']),
              _str(r['request_number']),
              _str(r['customer']),
              _str(r['product']),
              _qty(r['litres']),
              _str(r['station']),
              _str(r['omc']),
              _str(r['district']),
            ],
          )
          .toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exception monitoring overview',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _metric(
              'Repeat customer identifiers',
              _qty(repeats.length),
              Icons.repeat,
            ),
            _metric(
              'Potential monthly exceedances',
              _qty(flagged),
              Icons.warning_amber_outlined,
            ),
            _metric(
              'Pending confirmations',
              _qty(pending),
              Icons.hourglass_empty,
            ),
            _metric(
              'NOT_FUELED responses',
              _qty(notFueled),
              Icons.report_outlined,
            ),
          ],
        ),
        _note(
          'Pending and NOT_FUELED counts use confirmation-record dates for '
          'the selected reporting period. The report does not yet supply '
          'individual confirmation cases, so these counts cannot be opened '
          'as case-level records. NOT_FUELED requires MERA review and does '
          'not automatically cancel or reallocate fuel.',
        ),
        const SizedBox(height: 16),
        Text(
          'Repeated confirmed allocations',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _note(
          'Select a customer to inspect their confirmed allocations '
          'directly below, without opening another page.',
        ),
        if (repeats.isEmpty)
          _note(
            'No repeated confirmed allocations for the selected period or search.',
          )
        else
          Card(
            elevation: 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Confirmed allocations')),
                  DataColumn(label: Text('Total (L)')),
                  DataColumn(label: Text('Stations visited')),
                ],
                rows: repeats.map((r) {
                  final key = r['customer_key']?.toString();
                  final selected = key != null && key == selectedRepeat;
                  return DataRow(
                    selected: selected,
                    onSelectChanged: key == null
                        ? null
                        : (_) => setState(() {
                            _selectedExceptionCustomerKey = selected
                                ? null
                                : key;
                          }),
                    cells: [
                      DataCell(Text(_str(r['customer']))),
                      DataCell(Text(_qty(r['confirmed_allocations']))),
                      DataCell(Text(_qty(r['total_litres']))),
                      DataCell(Text(_qty(r['stations_visited']))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        if (selectedRepeat != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected customer — confirmed allocations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _selectedExceptionCustomerKey = null),
                icon: const Icon(Icons.close),
                label: const Text('Clear selection'),
              ),
            ],
          ),
          transactions(repeatHistory),
        ],
        _note(
          'Multiple allocations or stations are review indicators, '
          'not proof of duplicate physical visits or misconduct. '
          'One-off requests are not merged by customer name.',
        ),
        const SizedBox(height: 18),
        Text(
          'Active monthly allowances — current Malawi month',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _note(
          'Select a registered customer allowance to inspect that '
          'customer’s confirmed records within the selected report period.',
        ),
        if (allowances.isEmpty)
          _note('No monthly allowance records for the current filters.')
        else
          Card(
            elevation: 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Monthly limit (L)')),
                  DataColumn(label: Text('Confirmed this month (L)')),
                  DataColumn(label: Text('Remaining (L)')),
                  DataColumn(label: Text('Used (%)')),
                  DataColumn(label: Text('Review')),
                ],
                rows: allowances.map((r) {
                  final id = r['applicant_id']?.toString();
                  final selected = id != null && id == selectedApplicant;
                  return DataRow(
                    selected: selected,
                    onSelectChanged: id == null
                        ? null
                        : (_) => setState(() {
                            _selectedAllowanceApplicantId = selected
                                ? null
                                : id;
                          }),
                    cells: [
                      DataCell(Text(_str(r['customer']))),
                      DataCell(Text(_str(r['product']))),
                      DataCell(Text(_qty(r['limit_litres']))),
                      DataCell(Text(_qty(r['current_month_confirmed_litres']))),
                      DataCell(Text(_qty(r['remaining_litres']))),
                      DataCell(
                        Text(
                          r['utilization_percent'] == null
                              ? '—'
                              : '${_qty(r['utilization_percent'])}%',
                        ),
                      ),
                      DataCell(
                        Text(
                          r['potential_exceedance'] == true
                              ? 'Potential exceedance'
                              : '—',
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        const SizedBox(height: 10),
        for (final r in allowances) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_str(r['customer'])} — ${_str(r['product'])}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                r['utilization_percent'] == null
                    ? 'N/A'
                    : '${_qty(r['utilization_percent'])}%',
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (_num(r['utilization_percent']) / 100).clamp(0.0, 1.0),
            minHeight: 8,
            color: r['potential_exceedance'] == true ? Colors.red : Colors.teal,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 10),
        ],
        if (selectedApplicant != null) ...[
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected registered customer — confirmed history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _selectedAllowanceApplicantId = null),
                icon: const Icon(Icons.close),
                label: const Text('Clear selection'),
              ),
            ],
          ),
          transactions(applicantHistory),
          _note(
            'History above follows the selected report date range; '
            'monthly allowance usage above always uses the current Malawi month.',
          ),
        ],
        _note(
          '$flagged potential monthly allowance exceedance(s) among the '
          'displayed allowance rows. Petrol and Diesel limits are independent. '
          'Daily, weekly and per-session allowance checks are not yet provided '
          'by this reporting function. An alert requires verification before '
          'any enforcement decision.',
        ),
      ],
    );
  }

  Widget _exportsSection(Map<String, dynamic> report) {
    final history = _filterRows(_rows(report['history']));
    final customers = _filterRows(
      _rows(report['customers']),
      applyProduct: false,
    );
    final stations = _filterRows(
      _rows(report['stations']),
      applyProduct: false,
    );
    final omcs = _filterRows(_rows(report['omcs']), applyProduct: false);
    final districts = _filterRows(
      _rows(report['districts']),
      applyProduct: false,
    );
    final allowances = _filterRows(_rows(report['monthly_allowances']));
    final stamp = _date(_malawiNow());
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: history.isEmpty
              ? null
              : () => _export('mera_container_history_$stamp.csv', const [
                  'request_number',
                  'customer',
                  'company',
                  'product',
                  'litres',
                  'allocated_litres',
                  'dispensed_litres',
                  'confirmed_at',
                  'date',
                  'station',
                  'omc',
                  'district',
                ], history),
          icon: const Icon(Icons.download),
          label: const Text('Fueling history CSV'),
        ),
        OutlinedButton.icon(
          onPressed: customers.isEmpty
              ? null
              : () => _export('mera_container_customers_$stamp.csv', const [
                  'customer',
                  'company',
                  'petrol_litres',
                  'diesel_litres',
                  'total_litres',
                  'confirmed_allocations',
                  'stations_visited',
                ], customers),
          icon: const Icon(Icons.download),
          label: const Text('Customers CSV'),
        ),
        OutlinedButton.icon(
          onPressed: stations.isEmpty
              ? null
              : () => _export('mera_container_stations_$stamp.csv', const [
                  'station',
                  'omc',
                  'district',
                  'petrol_litres',
                  'diesel_litres',
                  'total_litres',
                  'confirmed_allocations',
                ], stations),
          icon: const Icon(Icons.download),
          label: const Text('Stations CSV'),
        ),
        OutlinedButton.icon(
          onPressed: omcs.isEmpty
              ? null
              : () => _export('mera_container_omcs_$stamp.csv', const [
                  'omc',
                  'petrol_litres',
                  'diesel_litres',
                  'total_litres',
                  'stations_used',
                  'confirmed_allocations',
                ], omcs),
          icon: const Icon(Icons.download),
          label: const Text('OMCs CSV'),
        ),
        OutlinedButton.icon(
          onPressed: districts.isEmpty
              ? null
              : () => _export('mera_container_districts_$stamp.csv', const [
                  'district',
                  'petrol_litres',
                  'diesel_litres',
                  'total_litres',
                  'stations_used',
                  'confirmed_allocations',
                ], districts),
          icon: const Icon(Icons.download),
          label: const Text('Districts CSV'),
        ),
        OutlinedButton.icon(
          onPressed: allowances.isEmpty
              ? null
              : () => _export(
                  'mera_container_monthly_allowances_$stamp.csv',
                  const [
                    'customer',
                    'product',
                    'allowance_type',
                    'limit_litres',
                    'current_month_confirmed_litres',
                    'remaining_litres',
                    'utilization_percent',
                    'potential_exceedance',
                  ],
                  allowances,
                ),
          icon: const Icon(Icons.download),
          label: const Text('Allowances CSV'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _range();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Container Fuel Monitoring',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh data',
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Confirmed container fuel consumption, requests, customers, locations and exceptions — all on one page.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in const [
                'Today',
                'Yesterday',
                'This Week',
                'This Month',
                'Custom Range',
                'All Time',
              ])
                ChoiceChip(
                  label: Text(p),
                  selected: _period == p,
                  onSelected: (_) => _choosePeriod(p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            range == null
                ? (_period == 'All Time'
                      ? 'Reporting period: All time'
                      : 'Choose a custom date range')
                : 'Reporting period: ${_date(range.start)} to ${_date(range.end)} (Malawi time)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (_period == 'Custom Range' && range == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Choose a start and end date.'),
              ),
            )
          else
            FutureBuilder<Map<String, dynamic>>(
              future: _report,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SelectableText(
                        'Unable to load monitoring report: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                final report = snapshot.data ?? <String, dynamic>{};
                final s = _map(report['summary']);
                final trends = _rows(
                  report[_trendGranularity == 'Weekly'
                      ? 'weekly_trends'
                      : _trendGranularity == 'Monthly'
                      ? 'monthly_trends'
                      : 'trends'],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      '1. Fuel Consumption Overview',
                      Icons.local_gas_station,
                      _overview(s),
                      initiallyExpanded: true,
                    ),
                    _section(
                      '2. Fuel Consumption Trends',
                      Icons.show_chart,
                      _trendChart(trends),
                      initiallyExpanded: true,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 310,
                            child: TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                labelText:
                                    'Search customers, stations or requests',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ),
                          DropdownButton<String>(
                            value: _product,
                            items: const ['All products', 'PETROL', 'DIESEL']
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _product = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    _section(
                      '3. Customer Fueling Analysis',
                      Icons.people_outline,
                      _customerSection(report),
                    ),
                    _section(
                      '4. Station, OMC and District Analysis',
                      Icons.store_outlined,
                      _geographySection(report),
                    ),
                    _section(
                      '5. Requests, Approvals and Dispensing',
                      Icons.assignment_turned_in_outlined,
                      _requestsSection(report),
                    ),
                    _section(
                      '6. Repeat Fueling and Exceptions',
                      Icons.warning_amber_outlined,
                      _exceptionsSection(report),
                    ),
                    _section(
                      '7. Reports and CSV Exports',
                      Icons.download_outlined,
                      _exportsSection(report),
                    ),
                    const SizedBox(height: 12),
                    _note(
                      'Source: authorized Supabase Container Fuel Monitoring V2 report. '
                      'Use Refresh to retrieve the latest data.',
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}

class _TrendPoint {
  const _TrendPoint(this.date, this.petrol, this.diesel);
  final String date;
  final double petrol;
  final double diesel;
}

class _TrendPlot extends StatefulWidget {
  const _TrendPlot({required this.points, required this.product});
  final List<_TrendPoint> points;
  final String product;
  @override
  State<_TrendPlot> createState() => _TrendPlotState();
}

class _TrendPlotState extends State<_TrendPlot> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final n = widget.points.length;
    final showPetrol = widget.product != 'DIESEL';
    final showDiesel = widget.product != 'PETROL';
    final maximum = widget.points.fold<double>(
      0,
      (m, p) => math.max(
        m,
        math.max(showPetrol ? p.petrol : 0, showDiesel ? p.diesel : 0),
      ),
    );
    final ceiling = maximum <= 0 ? 1.0 : maximum * 1.12;
    final plot = math.max(650.0, n * 52.0 + 95.0);
    return Column(
      children: [
        if (selected != null && selected! < n)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${widget.points[selected!].date}   Petrol: ${widget.points[selected!].petrol.toStringAsFixed(2)} L   '
              'Diesel: ${widget.points[selected!].diesel.toStringAsFixed(2)} L',
            ),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (n == 0) return;
              final dx = d.localPosition.dx;
              final x0 = 62.0;
              final x1 = plot - 20.0;
              final index = n == 1
                  ? 0
                  : (((dx - x0) / (x1 - x0)) * (n - 1)).round().clamp(0, n - 1);
              setState(() => selected = index);
            },
            child: CustomPaint(
              size: Size(plot, 245),
              painter: _TrendPainter(
                points: widget.points,
                ceiling: ceiling,
                showPetrol: showPetrol,
                showDiesel: showDiesel,
                selected: selected,
                gridColor: Theme.of(context).dividerColor,
                textColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.ceiling,
    required this.showPetrol,
    required this.showDiesel,
    required this.selected,
    required this.gridColor,
    required this.textColor,
  });
  final List<_TrendPoint> points;
  final double ceiling;
  final bool showPetrol;
  final bool showDiesel;
  final int? selected;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 62.0;
    const right = 20.0;
    const top = 16.0;
    const bottom = 43.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final axis = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    void text(
      String s,
      double x,
      double y, {
      double fontSize = 10,
      TextAlign align = TextAlign.center,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout(maxWidth: 110);
      painter.paint(
        canvas,
        Offset(x - (align == TextAlign.center ? painter.width / 2 : 0), y),
      );
    }

    for (var i = 0; i <= 4; i++) {
      final y = top + h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), axis);
      text(
        (ceiling * (4 - i) / 4).toStringAsFixed(ceiling >= 10 ? 0 : 1),
        25,
        y - 7,
      );
    }
    if (points.isEmpty) return;
    double x(int i) =>
        left + (points.length == 1 ? w / 2 : w * i / (points.length - 1));
    double y(double value) => top + h * (1 - value / ceiling);
    void line(Color color, double Function(_TrendPoint) value) {
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final xx = x(i), yy = y(value(points[i]));
        if (i == 0) {
          path.moveTo(xx, yy);
        } else {
          path.lineTo(xx, yy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(
          Offset(x(i), y(value(points[i]))),
          3.5,
          Paint()..color = color,
        );
      }
    }

    if (showPetrol) line(Colors.teal, (p) => p.petrol);
    if (showDiesel) line(Colors.blue, (p) => p.diesel);
    final step = math.max(1, (points.length / 15).ceil());
    for (var i = 0; i < points.length; i++) {
      if (i % step != 0 && i != points.length - 1) continue;
      final d = points[i].date;
      text(
        d.length >= 10 ? d.substring(5) : d,
        x(i),
        top + h + 9,
        fontSize: 10,
      );
    }
    if (selected != null && selected! < points.length) {
      canvas.drawLine(
        Offset(x(selected!), top),
        Offset(x(selected!), top + h),
        Paint()
          ..color = textColor.withValues(alpha: 0.55)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.ceiling != ceiling ||
      old.showPetrol != showPetrol ||
      old.showDiesel != showDiesel ||
      old.selected != selected ||
      old.gridColor != gridColor ||
      old.textColor != textColor;
}
