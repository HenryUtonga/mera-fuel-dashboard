import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _service = DashboardService();
  String _period = '7 Days';
  String _selectedReportingOmc = 'All OMCs';
  bool _loading = true;
  String? _error;
List<Map<String, dynamic>> _fuelings = [], _stations = [], _rates = [],
    _rejections = [], _intervals = [], _deliveries = [],
    _stationReporting = [], _omcReporting = [];
  static const _petrol = Color(0xFF18A94B);
  static const _diesel = Color(0xFFF4B41A);

  @override
  void initState() { super.initState(); _load(); }

  DateTime get _today {
    // Use Malawi (UTC+2) regardless of browser timezone.
    final now = DateTime.now().toUtc().add(const Duration(hours: 2));
    return DateTime.utc(now.year, now.month, now.day);
  }
  DateTime get _start => _today.subtract(Duration(days: switch (_period) {
    'Today' => 0, '30 Days' => 29, '90 Days' => 89, _ => 6,
  }));
  DateTime get _end => _today;
  String _day(DateTime d) => '${d.day}/${d.month}';
  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
  String _text(dynamic v) => v?.toString().trim() ?? '';
  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  bool _bool(dynamic v) => v == true || '$v'.toLowerCase() == 'true';
  String _fmt(num v) {
    final parts = v.round().toString().split('');
    final b = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) b.write(',');
      b.write(parts[i]);
    }
    return b.toString();
  }
  DateTime? _malawi(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return null;
    return parsed.toUtc().add(const Duration(hours: 2));
  }
  DateTime? _dateOnly(dynamic value) {
    final s = _text(value);
    if (s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }
  bool _within(DateTime d) {
    final key = DateTime.utc(d.year, d.month, d.day);
    return !key.isBefore(_start) && !key.isAfter(_end);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Future.wait([
        _service.getFuelingAnalytics(startDate: _start, endDate: _end),
        _service.getStationIntelligence(),
        _service.getStationConsumption(),
        _service.getStationRejections(),
        _service.getFuelConsumptionIntervals(),
        _service.getFuelDeliveryVariance(),
        _service.getStationReportingFreshness(),
        _service.getOmcReportingFreshness(),
        
      ]);
      if (!mounted) return;
setState(() {
  _fuelings = data[0];
  _stations = data[1];
  _rates = data[2];
  _rejections = data[3];
  _intervals = data[4];
  _deliveries = data[5];
  _stationReporting = data[6];
  _omcReporting = data[7];
  _loading = false;
});
} catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Map<String, Map<String, dynamic>> get _stationIndex => {
    for (final row in _stations) _text(row['filling_station_id']): row,
  };

  // An interval is an observed quantity between two physical stock counts.
  // It cannot be assigned to an exact hour or day without an estimation model.
  List<Map<String, dynamic>> get _observations => _intervals.where((r) {
    final end = _malawi(r['current_count_at']);
    return end != null && _within(end);
  }).toList();

  // Daily chart explicitly reports the date a reading CLOSED, not the date
  // fuel was necessarily consumed. Never fabricate hourly consumption.
  Map<DateTime, Map<String, double>> get _observedByClosingDay {
    final out = <DateTime, Map<String, double>>{};
    for (var d = _start; !d.isAfter(_end); d = d.add(const Duration(days: 1))) {
      out[d] = {'PETROL': 0, 'DIESEL': 0};
    }
    for (final r in _observations) {
      final product = _text(r['product']).toUpperCase();
      if (product != 'PETROL' && product != 'DIESEL') continue;
      final end = _malawi(r['current_count_at'])!;
      final key = DateTime.utc(end.year, end.month, end.day);
      out[key]![product] = (out[key]![product] ?? 0) + _num(r['consumption_litres']);
    }
    return out;
  }

  double _observed(String product) => _observations
      .where((r) => _text(r['product']).toUpperCase() == product)
      .fold(0.0, (sum, r) => sum + _num(r['consumption_litres']));

  int _reporting(String product) => _observations
      .where((r) => _text(r['product']).toUpperCase() == product)
      .map((r) => _text(r['filling_station_id'])).where((id) => id.isNotEmpty)
      .toSet().length;

  double _stock(String product) => _stations.fold(0.0, (sum, r) => sum +
      _num(r[product == 'PETROL' ? 'current_petrol_litres' : 'current_diesel_litres']));

  double _dailyRate(String product) => _rates.where((r) =>
      _text(r['product']).toUpperCase() == product &&
      _text(r['consumption_data_status']).toUpperCase() == 'SUFFICIENT')
      .fold(0.0, (sum, r) => sum + _num(r['estimated_daily_consumption_litres']));

  List<MapEntry<String, Map<String, double>>> _rank(String field) {
    final totals = <String, Map<String, double>>{};
    final stations = _stationIndex;
    for (final r in _observations) {
      final product = _text(r['product']).toUpperCase();
      if (product != 'PETROL' && product != 'DIESEL') continue;
      final station = stations[_text(r['filling_station_id'])];
      final name = field == 'filling_station_name'
          ? _text(station?['filling_station_name'])
          : _text(station?[field]);
      final label = name.isEmpty ? 'Unknown' : name;
      final entry = totals.putIfAbsent(label, () => {'PETROL': 0, 'DIESEL': 0});
      entry[product] = (entry[product] ?? 0) + _num(r['consumption_litres']);
    }
    final sorted = totals.entries.toList()..sort((a, b) =>
        ((b.value['PETROL'] ?? 0) + (b.value['DIESEL'] ?? 0))
        .compareTo((a.value['PETROL'] ?? 0) + (a.value['DIESEL'] ?? 0)));
    return sorted;
  }

  List<Map<String, dynamic>> get _periodDeliveries => _deliveries.where((r) {
    final d = _dateOnly(r['delivery_date']);
    return d != null && _within(d);
  }).toList();

  double _deliveryTotal(String product, String field) => _periodDeliveries
      .where((r) => _text(r['product']).toUpperCase() == product)
      .fold(0.0, (sum, r) => sum + _num(r[field]));

  List<Map<String, dynamic>> get _exceptions => _periodDeliveries.where((r) =>
      _text(r['comparison_status']) != 'MATCHED').toList()
      ..sort((a, b) => _num(b['variance_litres']).abs()
          .compareTo(_num(a['variance_litres']).abs()));

  Widget _panel(String title, String subtitle, Widget child) => Container(
    width: double.infinity, padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.black12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 18), child,
    ]),
  );

  Widget _stat(String label, String value, String note) => Container(
    width: 195, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4), Text(note, style: const TextStyle(fontSize: 11, color: Colors.black54)),
    ]),
  );

  Widget _legend() => const Wrap(spacing: 18, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, color: _petrol, size: 11), SizedBox(width: 6), Text('Petrol')]),
    Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, color: _diesel, size: 11), SizedBox(width: 6), Text('Diesel')]),
  ]);

  Widget _trend() {
    final entries = _observedByClosingDay.entries.toList();
    if (_observations.isEmpty) return const SizedBox(height: 150, child: Center(child: Text('No completed stock-count intervals in this period.')));
    final petrol = <FlSpot>[], diesel = <FlSpot>[];
    var maxY = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final p = entries[i].value['PETROL'] ?? 0;
      final d = entries[i].value['DIESEL'] ?? 0;
      maxY = math.max(maxY, math.max(p, d));
      petrol.add(FlSpot(i.toDouble(), p)); diesel.add(FlSpot(i.toDouble(), d));
    }
    return Column(children: [
      _legend(), const SizedBox(height: 14),
      SizedBox(height: 290, child: LineChart(LineChartData(
        minY: 0, maxY: math.max(1.0, maxY * 1.15),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 55)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
            interval: entries.length > 30 ? 10 : entries.length > 10 ? 5 : 1,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= entries.length || v != i.toDouble()) return const SizedBox.shrink();
              return Text(_day(entries[i].key), style: const TextStyle(fontSize: 10));
            },
          )),
        ),
        lineBarsData: [
          LineChartBarData(spots: petrol, color: _petrol, barWidth: 3, isCurved: false,
            dotData: FlDotData(show: entries.length <= 14)),
          LineChartBarData(spots: diesel, color: _diesel, barWidth: 3, isCurved: false,
            dotData: FlDotData(show: entries.length <= 14)),
        ],
        lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
            '${s.barIndex == 0 ? 'Petrol' : 'Diesel'}: ${_fmt(s.y)} L\nReading closed ${_day(entries[s.x.toInt()].key)}',
            const TextStyle(color: Colors.white),
          )).toList(),
        )),
      ))),
    ]);
  }

  Widget _ranking(List<MapEntry<String, Map<String, double>>> rows) {
    if (rows.isEmpty) return const Padding(padding: EdgeInsets.all(30), child: Text('No observed consumption in the selected period.'));
    final maxTotal = rows.map((e) => (e.value['PETROL'] ?? 0) + (e.value['DIESEL'] ?? 0))
        .fold<double>(1.0, (current, value) => math.max(current, value));
    return Column(children: [
      _legend(), const SizedBox(height: 14),
      ...rows.take(10).map((e) {
        final p = e.value['PETROL'] ?? 0, d = e.value['DIESEL'] ?? 0;
        return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${_fmt(p + d)} L', style: const TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 5),
            LinearProgressIndicator(value: p / maxTotal, color: _petrol, minHeight: 6,
              backgroundColor: Colors.black12),
            const SizedBox(height: 3),
            LinearProgressIndicator(value: d / maxTotal, color: _diesel, minHeight: 6,
              backgroundColor: Colors.black12),
            Text('Petrol ${_fmt(p)} L  •  Diesel ${_fmt(d)} L',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ));
      }),
    ]);
  }

Widget _supply() {
  Widget fuelStockCard(String product) {
    final stock = _stock(product);
    final daily = _dailyRate(product);
    final days = daily > 0 ? stock / daily : null;

    final Color statusColor;
    final String status;

    if (days == null) {
      statusColor = Colors.grey;
      status = 'INSUFFICIENT DATA';
    } else if (days < 1) {
      statusColor = Colors.red;
      status = 'CRITICAL';
    } else if (days < 2) {
      statusColor = Colors.orange;
      status = 'LOW';
    } else if (days < 3) {
      statusColor = Colors.amber.shade700;
      status = 'WATCH';
    } else {
      statusColor = Colors.green;
      status = 'ADEQUATE';
    }

    // Display up to seven days on the visual indicator.
    // This is not a measurement of tank capacity.
    final progress = days == null
        ? 0.0
        : (days / 7).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                product,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            '${_fmt(stock)} L',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const Text(
            'Current reported stock',
            style: TextStyle(color: Colors.black54),
          ),

          const SizedBox(height: 22),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Indicative days of stock'),
              Text(
                days == null
                    ? 'Insufficient data'
                    : '${days.toStringAsFixed(1)} days',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 20,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                statusColor,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Visual scale: 0–7 days',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 20),

          const Divider(),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated daily use'),
              Text(
                daily > 0
                    ? '${_fmt(daily)} L/day'
                    : 'Insufficient data',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  return LayoutBuilder(
    builder: (context, constraints) {
      final petrol = fuelStockCard('PETROL');
      final diesel = fuelStockCard('DIESEL');

      if (constraints.maxWidth < 800) {
        return Column(
          children: [
            petrol,
            const SizedBox(height: 16),
            diesel,
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: petrol),
          const SizedBox(width: 20),
          Expanded(child: diesel),
        ],
      );
    },
  );
}

Widget _deliveryComparison() {
  Widget fuelComparison(String product) {
    final expected = _deliveryTotal(product, 'expected_litres');
    final actual = _deliveryTotal(product, 'actual_litres');

    final percentage = expected > 0
        ? (actual / expected * 100)
        : 0.0;

    final barScale = expected > actual ? expected : actual;

    Widget comparisonBar(
      String label,
      double litres,
      Color color,
    ) {
      final fraction = barScale > 0
          ? (litres / barScale).clamp(0.0, 1.0)
          : 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                '${_fmt(litres)} L',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 18,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              product,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              expected > 0
                  ? '${percentage.toStringAsFixed(1)}% recorded'
                  : 'No expected volume',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        comparisonBar(
          'Expected deliveries',
          expected,
          Colors.blue,
        ),

        const SizedBox(height: 18),

        comparisonBar(
          'Recorded receipts',
          actual,
          Colors.green,
        ),

        const SizedBox(height: 14),

        Text(
          'Difference: ${_fmt(actual - expected)} L',
          style: const TextStyle(
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      fuelComparison('PETROL'),

      const SizedBox(height: 28),
      const Divider(),
      const SizedBox(height: 28),

      fuelComparison('DIESEL'),

      const SizedBox(height: 28),
      const Divider(),
      const SizedBox(height: 12),

      const Text(
        'Same-day station/product comparison only. '
        'Different-day arrivals, missing attendant entries '
        'and future schedules are not reconciled. '
        'A difference does NOT establish non-delivery '
        'or an unauthorized receipt.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    ],
  );
}

  Widget _exceptionsTable() {
  final exceptions = _exceptions;
  final stations = _stationIndex;

  final noReceipt = exceptions.where(
    (r) => _text(r['comparison_status']) == 'NO_SAME_DAY_RECEIPT',
  ).length;

  final unmatched = exceptions.where(
    (r) => _text(r['comparison_status']) == 'UNMATCHED_RECEIPT',
  ).length;

  final partial = exceptions.where(
    (r) => _text(r['comparison_status']) == 'PARTIAL',
  ).length;

  final excess = exceptions.where(
    (r) => _text(r['comparison_status']) == 'EXCESS',
  ).length;

  Widget summaryCard(
    String title,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1000
              ? 4
              : width >= 550
                  ? 2
                  : 1;

          final cardWidth =
              (width - (columns - 1) * 12) / columns;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: cardWidth,
                child: summaryCard(
                  'No same-day receipt',
                  noReceipt,
                  Colors.red,
                  Icons.warning_amber_rounded,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: summaryCard(
                  'Unmatched receipts',
                  unmatched,
                  Colors.orange,
                  Icons.local_shipping_outlined,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: summaryCard(
                  'Partial receipts',
                  partial,
                  Colors.amber.shade800,
                  Icons.trending_down,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: summaryCard(
                  'Excess receipts',
                  excess,
                  Colors.blue,
                  Icons.trending_up,
                ),
              ),
            ],
          );
        },
      ),

      const SizedBox(height: 24),

      Text(
        '${exceptions.length} station/product/day records need reconciliation',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
      ),

      const SizedBox(height: 12),

      if (exceptions.isEmpty)
        const Text(
          'No same-day reconciliation differences in this period.',
        )
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Station')),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Expected L')),
              DataColumn(label: Text('Recorded L')),
              DataColumn(label: Text('Difference L')),
              DataColumn(label: Text('Preliminary status')),
            ],
            rows: exceptions.take(30).map((r) {
              final station =
                  stations[_text(r['filling_station_id'])];

              final status = switch (
                  _text(r['comparison_status'])) {
                'NO_SAME_DAY_RECEIPT' =>
                  'No same-day receipt recorded',
                'UNMATCHED_RECEIPT' =>
                  'No same-day expectation',
                'PARTIAL' =>
                  'Recorded less than expected',
                'EXCESS' =>
                  'Recorded more than expected',
                _ => _text(r['comparison_status']),
              };

              return DataRow(
                cells: [
                  DataCell(
                    Text(_text(r['delivery_date'])),
                  ),
                  DataCell(
                    SizedBox(
                      width: 170,
                      child: Text(
                        _text(
                          station?['filling_station_name'],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(_text(r['product'])),
                  ),
                  DataCell(
                    Text(
                      _fmt(_num(r['expected_litres'])),
                    ),
                  ),
                  DataCell(
                    Text(
                      _fmt(_num(r['actual_litres'])),
                    ),
                  ),
                  DataCell(
                    Text(
                      _fmt(_num(r['variance_litres'])),
                    ),
                  ),
                  DataCell(
                    Text(status),
                  ),
                ],
              );
            }).toList(),
          ),
        ),

      if (exceptions.length > 30)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Showing 30 of ${exceptions.length} differences.',
            style: const TextStyle(
              color: Colors.black54,
            ),
          ),
        ),

      const SizedBox(height: 12),

      const Text(
        'These categories are based on same-day station/product '
        'comparisons. They do not establish whether a delivery '
        'failed, arrived on another date, or was entered late.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    ],
  );
}

Widget _control() {
  final rejections = _rejections.fold(
    0, (int s, r) => s + _int(r['rejection_count']),
  );

  final already = _rejections.fold(
    0, (int s, r) => s + _int(r['already_fueled_count']),
  );

  final invalid = _rejections.fold(
    0, (int s, r) => s + _int(r['invalid_count']),
  );

  final identifiers = _rejections.fold(
    0, (int s, r) => s + _int(r['identifier_conflict_count']),
  );

  final syncConflicts = _fuelings
      .where((r) => _bool(r['sync_conflict']))
      .length;

  final overrides = _fuelings
      .where((r) => _bool(r['override_used']))
      .length;

  final other = rejections - already - invalid - identifiers;

  final categories = <({String label, int count, Color color})>[
    (
      label: 'Already fueled',
      count: already,
      color: Colors.orange,
    ),
    (
      label: 'Invalid attempts',
      count: invalid,
      color: Colors.red,
    ),
    (
      label: 'Identifier conflicts',
      count: identifiers,
      color: Colors.purple,
    ),
    if (other > 0)
      (
        label: 'Other rejections',
        count: other,
        color: Colors.blueGrey,
      ),
  ];

  final categoryTotal = categories.fold<int>(
    0, (sum, item) => sum + item.count,
  );

  Widget donutChart() {
    if (categoryTotal == 0) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: Text('No rejection categories recorded'),
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: 65,
          sectionsSpace: 3,
          startDegreeOffset: -90,
          sections: categories
              .where((item) => item.count > 0)
              .map(
                (item) => PieChartSectionData(
                  value: item.count.toDouble(),
                  color: item.color,
                  radius: 35,
                  showTitle: false,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget legend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rejection breakdown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        for (final item in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label),
                ),
                Text(
                  _fmt(item.count),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),
        const Text(
          'Cumulative rejection data',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _stat(
            'Rejections',
            _fmt(rejections),
            'Cumulative rejection view',
          ),
          _stat(
            'Already fueled',
            _fmt(already),
            'Cumulative rejection view',
          ),
          _stat(
            'Invalid attempts',
            _fmt(invalid),
            'Cumulative rejection view',
          ),
          _stat(
            'Identifier conflicts',
            _fmt(identifiers),
            'Cumulative rejection view',
          ),
          _stat(
            'Sync conflicts',
            _fmt(syncConflicts),
            'Selected period',
          ),
          _stat(
            'Overrides',
            _fmt(overrides),
            'Selected period',
          ),
        ],
      ),

      const SizedBox(height: 30),
      const Divider(),
      const SizedBox(height: 20),

      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                donutChart(),
                const SizedBox(height: 20),
                legend(),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: donutChart()),
              const SizedBox(width: 30),
              Expanded(child: legend()),
            ],
          );
        },
      ),

      const SizedBox(height: 12),

      const Text(
        'The donut chart shows cumulative rejection categories. '
        'Sync conflicts and overrides relate to the selected '
        'reporting period and are not included in the chart.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    ],
  );
}

  Widget _riskTable() {
  final stations = _stationIndex;

  final rows = <({
    String station,
    String product,
    double? stock,
    double daily,
    double? days,
  })>[];

  for (final r in _rates) {
    if (_text(r['consumption_data_status']).toUpperCase() !=
        'SUFFICIENT') {
      continue;
    }

    final product = _text(r['product']).toUpperCase();

    if (product != 'PETROL' && product != 'DIESEL') {
      continue;
    }

    final station = stations[_text(r['filling_station_id'])];

    if (station == null) {
      continue;
    }

    final daily = _num(
      r['estimated_daily_consumption_litres'],
    );

    if (daily <= 0) {
      continue;
    }

    final stockField = product == 'PETROL'
        ? 'current_petrol_litres'
        : 'current_diesel_litres';

    final rawStock = station[stockField];

    // Missing stock is not equivalent to zero stock.
    final double? stock =
        rawStock == null || rawStock.toString().trim().isEmpty
            ? null
            : double.tryParse(rawStock.toString());

    final double? days =
        stock == null ? null : stock / daily;

    rows.add((
      station: _text(station['filling_station_name']),
      product: product,
      stock: stock,
      daily: daily,
      days: days,
    ));
  }

  // Lowest confirmed days first; missing data last.
  rows.sort((a, b) {
    if (a.days == null && b.days == null) return 0;
    if (a.days == null) return 1;
    if (b.days == null) return -1;
    return a.days!.compareTo(b.days!);
  });

  if (rows.isEmpty) {
    return const Text(
      'Insufficient observations for stock risk projections.',
    );
  }

  Color riskColor(double? days) {
    if (days == null) return Colors.grey;
    if (days < 1) return Colors.red;
    if (days < 2) return Colors.orange;
    if (days < 3) return Colors.amber.shade800;
    return Colors.green;
  }

  String riskLabel(double? days) {
    if (days == null) return 'NO STOCK DATA';
    if (days < 1) return 'CRITICAL';
    if (days < 2) return 'LOW';
    if (days < 3) return 'WATCH';
    return 'ADEQUATE';
  }

  Widget daysIndicator(double? days) {
    if (days == null) {
      return const Text(
        'Not reported',
        style: TextStyle(color: Colors.grey),
      );
    }

    final progress = (days / 7).clamp(0.0, 1.0).toDouble();
    final color = riskColor(days);

    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${days.toStringAsFixed(1)} days',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  final missing = rows.where((r) => r.stock == null).length;
  final critical =
      rows.where((r) => r.days != null && r.days! < 1).length;
  final low = rows.where(
    (r) => r.days != null && r.days! >= 1 && r.days! < 2,
  ).length;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _stat(
            'Critical',
            _fmt(critical),
            'Less than 1 estimated day',
          ),
          _stat(
            'Low',
            _fmt(low),
            '1–2 estimated days',
          ),
          _stat(
            'Missing stock data',
            _fmt(missing),
            'Cannot assess stock risk',
          ),
        ],
      ),

      const SizedBox(height: 24),

      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Station')),
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('Stock L')),
            DataColumn(label: Text('Est. L/day')),
            DataColumn(label: Text('Days remaining')),
            DataColumn(label: Text('Risk')),
          ],
          rows: rows.take(25).map((r) {
            final color = riskColor(r.days);

            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 240,
                    child: Text(
                      r.station,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(r.product)),
                DataCell(
                  Text(
                    r.stock == null
                        ? 'Not reported'
                        : _fmt(r.stock!),
                  ),
                ),
                DataCell(Text(_fmt(r.daily))),
                DataCell(daysIndicator(r.days)),
                DataCell(
                  Text(
                    riskLabel(r.days),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),

      const SizedBox(height: 12),

      Text(
        'Showing ${rows.length < 25 ? rows.length : 25} '
        'of ${rows.length} eligible station/product records.',
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),

      const SizedBox(height: 8),

      const Text(
        'Risk is estimated from the latest available stock '
        'and station-specific daily consumption. Missing '
        'stock values are not treated as zero. '
        'Stock reporting freshness must be verified separately.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.black54,
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    if (_loading) {
  return const Center(child: CircularProgressIndicator());
}
   if (_error != null) {
  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Unable to load analytics'), const SizedBox(height: 8),
      SelectableText(_error!), const SizedBox(height: 12),
      FilledButton(onPressed: _load, child: const Text('Retry')),
    ]));
   }
    return RefreshIndicator(onRefresh: _load, child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24), child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, spacing: 20, runSpacing: 12, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Fuel Analytics', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                Text('${_date(_start)} – ${_date(_end)} (Malawi time)',
                  style: const TextStyle(color: Colors.black54)),
              ]),
              Wrap(spacing: 8, children: [
                for (final p in ['Today', '7 Days', '30 Days', '90 Days'])
                  ChoiceChip(label: Text(p), selected: _period == p,
                    onSelected: (_) { setState(() => _period = p); _load(); }),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ]),
            ]),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _stat('Observed petrol use', '${_fmt(_observed('PETROL'))} L', '${_reporting('PETROL')} reporting stations'),
              _stat('Observed diesel use', '${_fmt(_observed('DIESEL'))} L', '${_reporting('DIESEL')} reporting stations'),
              _stat('Petrol stock', '${_fmt(_stock('PETROL'))} L', 'Latest reported balances'),
              _stat('Diesel stock', '${_fmt(_stock('DIESEL'))} L', 'Latest reported balances'),
              _stat('Fueling transactions', _fmt(_fuelings.length), 'Compliance activity, not consumption'),
              _stat('Vehicles', _fmt(_fuelings.map((r) {
                final id = _text(r['vehicle_id']);
                if (id.isNotEmpty) return id;
                final code = _text(r['vehicle_code']);
                return code.isNotEmpty ? code : _text(r['plate_number']);
              }).where((s) => s.isNotEmpty).toSet().length), 'Unique in selected period'),
            ]),
            const SizedBox(height: 20),
            _panel('Observed Fuel Consumption',
              'Litres calculated from consecutive physical stock counts and intervening receipts. '
              'Each interval is plotted on its closing-reading date, NOT as exact daily use.', _trend()),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final a = _panel('Regional Consumption', 'Observed litres by station region; selected closing-reading period.', _ranking(_rank('region')));
              final b = _panel('OMC Consumption', 'Observed litres by current station OMC.', _ranking(_rank('omc')));
              return c.maxWidth < 950 ? Column(children: [a, const SizedBox(height: 20), b]) :
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 20), Expanded(child: b)]);
            }),
            const SizedBox(height: 20),
            _panel('Station Consumption', 'Top stations by observed litres; partial coverage, not a national ranking.',
              _ranking(_rank('filling_station_name'))),
            const SizedBox(height: 20),
            _panel('Supply & Estimated Days of Stock',
              'Physical stock and estimated daily consumption from stations with sufficient observations. '
              'National stock divided by partial-coverage consumption is indicative only.', _supply()),
            const SizedBox(height: 20),
            _panel('Expected vs Recorded Deliveries',
              'Same Malawi calendar period for expected schedules and recorded receipts.', _deliveryComparison()),
            const SizedBox(height: 20),
            _panel('Delivery Reconciliation Exceptions',
              'Preliminary same-day differences; future schedules and cross-day deliveries may appear unmatched.',
              _exceptionsTable()),
            const SizedBox(height: 20),
            _panel('Fuel Control & Exceptions',
              'Fueling transactions are compliance events; rejection totals are cumulative.', _control()),
            const SizedBox(height: 20),
            _panel('Stations at Supply Risk',
              'Based on latest reported stock and eligible station-specific daily use estimates.', _riskTable()),
            const SizedBox(height: 20),
_panel(
  'Station Reporting Coverage & Freshness',
  'Physical stock-count submissions by operational filling stations.',
  Builder(
    builder: (context) {
      final total = _stationReporting.length;
      final reported = _stationReporting.where((r) {
        final last = _malawi(r['last_report_at']);
        return last != null && _within(last);
      }).length;
      final notReported = total - reported;
      final percentage = total == 0 ? 0.0 : reported * 100 / total;
final now = DateTime.now().toUtc();

int freshnessCount(Duration? minimum, Duration? maximum) {
  return _stationReporting.where((r) {
    final last = DateTime.tryParse('${r['last_report_at']}');
    if (last == null) return false;

    final age = now.difference(last.toUtc());

    if (age.isNegative) return false;
    if (minimum != null && age <= minimum) return false;
    if (maximum != null && age > maximum) return false;

    return true;
  }).length;
}

final within24h = freshnessCount(
  null,
  const Duration(hours: 24),
);

final between24and48h = freshnessCount(
  const Duration(hours: 24),
  const Duration(hours: 48),
);

final between48hAnd7d = freshnessCount(
  const Duration(hours: 48),
  const Duration(days: 7),
);

final olderThan7d = freshnessCount(
  const Duration(days: 7),
  null,
);

final neverReported = _stationReporting
    .where((r) => r['last_report_at'] == null)
    .length;

final overdueStations = _stationReporting.where((r) {
  final omc = _text(r['omc']);

  if (_selectedReportingOmc != 'All OMCs' &&
      omc != _selectedReportingOmc) {
    return false;
  }

  final last = DateTime.tryParse('${r['last_report_at']}');

  if (last == null) return true;

  return now.difference(last.toUtc()) >
      const Duration(days: 7);
}).toList();

overdueStations.sort((a, b) {
  final aDate = DateTime.tryParse('${a['last_report_at']}');
  final bDate = DateTime.tryParse('${b['last_report_at']}');

  if (aDate == null && bDate != null) return -1;
  if (aDate != null && bDate == null) return 1;

  if (aDate != null && bDate != null) {
    return aDate.compareTo(bDate);
  }

  return _text(a['filling_station_name'])
      .compareTo(_text(b['filling_station_name']));
});

return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(
                'Operational stations',
                _fmt(total),
                'Eligible active operational stations',
              ),
              _stat(
                'Stations reporting',
                _fmt(reported),
                'Stock counts in selected period',
              ),
              _stat(
                'Not reporting',
                _fmt(notReported),
                'No stock count in selected period',
              ),
              _stat(
                'Reporting coverage',
                '${percentage.toStringAsFixed(1)}%',
                'Selected period',
              ),
            ],
          ),

          const SizedBox(height: 24),

const Text(
  'Reporting Freshness',
  style: TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 8),

const Text(
  'Time since each station last submitted a physical stock count. '
  'Calculated from the current time, independently of the selected period.',
  style: TextStyle(
    fontSize: 12,
    color: Colors.black54,
  ),
),

const SizedBox(height: 16),

Wrap(
  spacing: 12,
  runSpacing: 12,
  children: [
    _stat(
      'Within 24 hours',
      _fmt(within24h),
      'Latest report within 24 hours',
    ),
    _stat(
      '24–48 hours',
      _fmt(between24and48h),
      'Latest report 1–2 days ago',
    ),
    _stat(
      '48 hours–7 days',
      _fmt(between48hAnd7d),
      'Latest report 2–7 days ago',
    ),
    _stat(
      'Older than 7 days',
      _fmt(olderThan7d),
      'Last report over 7 days ago',
    ),
    _stat(
      'Never reported',
      _fmt(neverReported),
      'No physical stock count recorded',
    ),
  ],
),

const SizedBox(height: 24),
const Divider(),
const SizedBox(height: 16),

const SizedBox(height: 12),

DropdownButtonFormField<String>(
  key: ValueKey(_selectedReportingOmc),
  initialValue: _selectedReportingOmc,
  decoration: const InputDecoration(
    labelText: 'Filter filling stations by OMC',
    border: OutlineInputBorder(),
    prefixIcon: Icon(Icons.filter_list),
  ),
  isExpanded: true,
  items: [
    'All OMCs',
    ..._stationReporting
        .map((r) => _text(r['omc']))
        .where((omc) => omc.isNotEmpty)
        .toSet()
        .toList()
      ..sort(),
  ].map((omc) {
    return DropdownMenuItem<String>(
      value: omc,
      child: Text(omc),
    );
  }).toList(),
  onChanged: (value) {
    if (value == null) return;
    setState(() {
      _selectedReportingOmc = value;
    });
  },
),

const SizedBox(height: 16),

Text(
  'Stations Requiring Reporting Follow-up (${overdueStations.length})',
  style: const TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 8),

const Text(
  'Operational stations with no recorded physical stock count '
  'or whose latest count is more than seven days old.',
  style: TextStyle(fontSize: 12, color: Colors.black54),
),

const SizedBox(height: 16),

if (overdueStations.isEmpty)
  const Text('No stations currently require reporting follow-up.')
else
SizedBox(
  height: 400,
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
      columns: const [
        DataColumn(label: Text('Station')),
        DataColumn(label: Text('OMC')),
        DataColumn(label: Text('Last stock count')),
        DataColumn(label: Text('Status')),
      ],
      rows: overdueStations.map((r) {
        final last = _malawi(r['last_report_at']);
        final status = last == null
            ? 'NEVER REPORTED'
            : 'OLDER THAN 7 DAYS';

        return DataRow(
          cells: [
DataCell(
  SizedBox(
    width: 350,
    child: Text(
      _text(r['filling_station_name']),
      softWrap: true,
    ),
  ),
),
            DataCell(Text(_text(r['omc']))),
            DataCell(
              Text(
                last == null
                    ? 'Never'
                    : '${_date(last)} '
                      '${last.hour.toString().padLeft(2, '0')}:'
                      '${last.minute.toString().padLeft(2, '0')}',
              ),
            ),
            DataCell(
              Text(
                status,
                style: TextStyle(
                  color: last == null ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      }).toList(),
        ), // Closes DataTable
      ),   // Closes horizontal SingleChildScrollView
    ),     // Closes vertical SingleChildScrollView
  ),       // Closes SizedBox


          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: total == 0 ? 0 : reported / total,
            minHeight: 14,
            backgroundColor: Colors.grey.shade200,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          const Text(
            'Reporting means at least one valid physical stock-count '
            'submission during the selected period. It does not '
            'measure whether a station met a required reporting '
            'frequency. Freshness will be shown separately.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    },
  ),
),


_panel(
  'OMC Expected Delivery Reporting',
  'Reporting activity by registered Oil Marketing Companies.',
  Builder(
    builder: (context) {
      final total = _omcReporting.length;

      final everReported = _omcReporting
          .where((r) => (r['total_submissions'] as num? ?? 0) > 0)
          .length;

      final neverReported = total - everReported;

return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _stat(
            'Active OMCs',
            _fmt(total),
            'Excludes N/A and unassigned',
          ),
          _stat(
            'Ever reported',
            _fmt(everReported),
            'At least one expected-delivery submission',
          ),
           _stat(
            'Never reported',
            _fmt(neverReported),
            'No expected-delivery submissions recorded',
          ),
        ],
      ),
const SizedBox(height: 24),
const Divider(),
const SizedBox(height: 16),

const Text(
  'OMC Reporting Status',
  style: TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 8),

const Text(
  'Historical expected-delivery submissions by OMC. '
  'Companies that have never submitted are listed first.',
  style: TextStyle(fontSize: 12, color: Colors.black54),
),

const SizedBox(height: 16),

SizedBox(
  height: 400,
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('OMC')),
          DataColumn(label: Text('Total submissions')),
          DataColumn(label: Text('Last submission')),
          DataColumn(label: Text('Status')),
        ],
        rows: (_omcReporting.toList()
              ..sort((a, b) {
                final countCompare = _int(a['total_submissions'])
                    .compareTo(_int(b['total_submissions']));
                if (countCompare != 0) return countCompare;
                return _text(a['omc_name'])
                    .compareTo(_text(b['omc_name']));
              }))
            .map((r) {
          final count = _int(r['total_submissions']);
          final last = _malawi(r['last_submission_at']);
          final reported = count > 0;

          return DataRow(
            cells: [
              DataCell(
                SizedBox(
                  width: 230,
                  child: Text(_text(r['omc_name'])),
                ),
              ),
              DataCell(Text(_fmt(count))),
              DataCell(
                Text(
                  last == null
                      ? 'Never'
                      : '${_date(last)} '
                        '${last.hour.toString().padLeft(2, '0')}:'
                        '${last.minute.toString().padLeft(2, '0')}',
                ),
              ),
              DataCell(
                Text(
                  reported ? 'REPORTED' : 'NEVER REPORTED',
                  style: TextStyle(
                    color: reported ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    ),
  ),
),

    ],
  );
    },
  ),
),

const SizedBox(height: 20),

_panel(
  'Reporting Coverage & Limitations',
  'Stations with valid stock-count intervals contributing to observed consumption.',
  LayoutBuilder(
    builder: (context, constraints) {
      final petrol = _reporting('PETROL');
      final diesel = _reporting('DIESEL');

      // These are counts of stations contributing observations,
      // not percentages of all stations.
      Widget reportingCard(
        String product,
        int count,
        Color color,
        IconData icon,
      ) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fmt(count),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const Text(
                      'Stations with valid intervals',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      final petrolCard = reportingCard(
        'PETROL',
        petrol,
        Colors.blue,
        Icons.local_gas_station,
      );

      final dieselCard = reportingCard(
        'DIESEL',
        diesel,
        Colors.green,
        Icons.local_gas_station,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (constraints.maxWidth >= 700)
            Row(
              children: [
                Expanded(child: petrolCard),
                const SizedBox(width: 16),
                Expanded(child: dieselCard),
              ],
            )
          else
            Column(
              children: [
                petrolCard,
                const SizedBox(height: 16),
                dieselCard,
              ],
            ),

          const SizedBox(height: 24),

          const Divider(),

          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: Colors.blueGrey,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmt(_observations.length),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Valid stock-count intervals closed in the selected period',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blueGrey,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'These figures show stations contributing valid '
                    'consumption observations, not the percentage of '
                    'all stations reporting. Intervals spanning multiple '
                    'days cannot establish exact hourly consumption. '
                    'Unreported stations and incomplete readings are '
                    'not treated as zero consumption.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  ),
),
          ],
        ),
      )),
    ));
  }
}