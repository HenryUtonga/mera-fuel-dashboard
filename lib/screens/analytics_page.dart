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
  final DashboardService _service = DashboardService();

  bool _loading = true;
  String? _error;

  String _selectedPeriod = '7 Days';

  List<Map<String, dynamic>> _fuelings = [];
  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _consumption = [];
  List<Map<String, dynamic>> _rejections = [];
  List<Map<String, dynamic>> _regionalReceipts = [];
  List<Map<String, dynamic>> _expectedDeliveries = [];

  static const List<String> _periods = [
    'Today',
    '7 Days',
    '30 Days',
    '90 Days',
  ];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _startDate {
    switch (_selectedPeriod) {
      case 'Today':
        return _today;
      case '30 Days':
        return _today.subtract(const Duration(days: 29));
      case '90 Days':
        return _today.subtract(const Duration(days: 89));
      case '7 Days':
      default:
        return _today.subtract(const Duration(days: 6));
    }
  }

  DateTime get _endDate => _today;

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getFuelingAnalytics(startDate: _startDate, endDate: _endDate),
        _service.getStationIntelligence(),
        _service.getStationConsumption(),
        _service.getStationRejections(),
        _service.getRegionalFuelReceipts(),
      ]);

      final expected = <Map<String, dynamic>>[];

      // Expected deliveries are currently exposed by calendar day.
      // Load each day in the selected analytics period.
      var day = _startDate;
      while (!day.isAfter(_endDate)) {
        final rows = await _service.getExpectedDeliveries(date: day);
        expected.addAll(rows);
        day = day.add(const Duration(days: 1));
      }

      if (!mounted) return;

      setState(() {
        _fuelings = results[0];
        _stations = results[1];
        _consumption = results[2];
        _rejections = results[3];
        _regionalReceipts = results[4];
        _expectedDeliveries = expected;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changePeriod(String period) async {
    if (_selectedPeriod == period) return;

    setState(() {
      _selectedPeriod = period;
    });

    await _loadAnalytics();
  }

  String _text(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  double _number(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _integer(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _boolean(dynamic value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  String _formatNumber(num value) {
    final rounded = value.round().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < rounded.length; i++) {
      final remaining = rounded.length - i;
      buffer.write(rounded[i]);

      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }

    return buffer.toString();
  }

  String _formatLitres(double value) {
    return '${_formatNumber(value)} L';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  DateTime? _malawiDate(dynamic value) {
    if (value == null) return null;

    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return null;

    final malawi = parsed.toUtc().add(const Duration(hours: 2));

    return DateTime(
      malawi.year,
      malawi.month,
      malawi.day,
      malawi.hour,
      malawi.minute,
      malawi.second,
    );
  }

  String _stationId(Map<String, dynamic> row) {
    return _text(row['filling_station_id']);
  }

  String _stationName(Map<String, dynamic> row) {
    final name = _text(row['filling_station_name']);
    return name.isEmpty ? 'Unknown Station' : name;
  }

  String _vehicleKey(Map<String, dynamic> row) {
    final vehicleId = _text(row['vehicle_id']);
    if (vehicleId.isNotEmpty) return 'ID:$vehicleId';

    final vehicleCode = _text(row['vehicle_code']);
    if (vehicleCode.isNotEmpty) return 'CODE:$vehicleCode';

    final plate = _text(row['plate_number']);
    if (plate.isNotEmpty) return 'PLATE:$plate';

    return '';
  }

  int get _totalFuelings => _fuelings.length;

  int get _uniqueVehicles {
    final values = <String>{};

    for (final row in _fuelings) {
      final key = _vehicleKey(row);
      if (key.isNotEmpty) values.add(key);
    }

    return values.length;
  }

  int get _activeStations {
    return _fuelings
        .map(_stationId)
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
  }

  int get _syncConflicts {
    return _fuelings.where((row) => _boolean(row['sync_conflict'])).length;
  }

  int get _overrides {
    return _fuelings.where((row) => _boolean(row['override_used'])).length;
  }

  int get _totalRejections {
    return _rejections.fold(
      0,
      (sum, row) => sum + _integer(row['rejection_count']),
    );
  }

  double get _expectedLitres {
    return _expectedDeliveries.fold(
      0,
      (sum, row) => sum + _number(row['quantity_litres']),
    );
  }

  double get _currentPetrolStock {
    return _stations.fold(
      0,
      (sum, row) => sum + _number(row['current_petrol_litres']),
    );
  }

  double get _currentDieselStock {
    return _stations.fold(
      0,
      (sum, row) => sum + _number(row['current_diesel_litres']),
    );
  }

  Map<String, Map<String, dynamic>> get _consumptionByStationProduct {
    final result = <String, Map<String, dynamic>>{};

    for (final row in _consumption) {
      final stationId = _text(row['filling_station_id']);
      final product = _text(row['product']).toUpperCase();

      if (stationId.isEmpty || product.isEmpty) continue;

      result['$stationId|$product'] = row;
    }

    return result;
  }

  double _dailyConsumptionForProduct(String product) {
    var total = 0.0;

    for (final row in _consumption) {
      if (_text(row['product']).toUpperCase() != product) continue;

      if (_text(row['consumption_data_status']).toUpperCase() != 'SUFFICIENT') {
        continue;
      }

      total += _number(row['estimated_daily_consumption_litres']);
    }

    return total;
  }

  double get _petrolDailyConsumption {
    return _dailyConsumptionForProduct('PETROL');
  }

  double get _dieselDailyConsumption {
    return _dailyConsumptionForProduct('DIESEL');
  }

  double? _daysRemaining(double stock, double dailyConsumption) {
    if (dailyConsumption <= 0) return null;
    return stock / dailyConsumption;
  }

Map<DateTime, Map<String, int>> get _fuelingsByDay {
  final result = <DateTime, Map<String, int>>{};

  var day = _startDate;
  while (!day.isAfter(_endDate)) {
    result[day] = {
      'PETROL': 0,
      'DIESEL': 0,
    };
    day = day.add(const Duration(days: 1));
  }

  for (final row in _fuelings) {
    final date = _malawiDate(row['fueled_at']);
    if (date == null) continue;

    final key = DateTime(date.year, date.month, date.day);

    if (!result.containsKey(key)) continue;

    final product = _text(row['fuel_type']).toUpperCase();

    if (product == 'PETROL' || product == 'DIESEL') {
      result[key]![product] = (result[key]![product] ?? 0) + 1;
    }
  }

  return result;
}

Map<int, Map<String, int>> get _fuelingsByHour {
  final result = <int, Map<String, int>>{
    for (var hour = 0; hour < 24; hour++)
      hour: {
        'PETROL': 0,
        'DIESEL': 0,
      },
  };

  for (final row in _fuelings) {
    final date = _malawiDate(row['fueled_at']);
    if (date == null) continue;

    final product = _text(row['fuel_type']).toUpperCase();

    if (product == 'PETROL' || product == 'DIESEL') {
      result[date.hour]![product] =
          (result[date.hour]![product] ?? 0) + 1;
    }
  }

  return result;
}

List<MapEntry<String, Map<String, int>>> get _fuelingsByStation {
  final result = <String, Map<String, int>>{};

  for (final row in _fuelings) {
    final station = _stationName(row);
    final product = _text(row['fuel_type']).toUpperCase();

    if (product != 'PETROL' && product != 'DIESEL') continue;

    result.putIfAbsent(
      station,
      () => {
        'PETROL': 0,
        'DIESEL': 0,
      },
    );

    result[station]![product] =
        (result[station]![product] ?? 0) + 1;
  }

  final entries = result.entries.toList()
    ..sort((a, b) {
      final aTotal =
          (a.value['PETROL'] ?? 0) + (a.value['DIESEL'] ?? 0);
      final bTotal =
          (b.value['PETROL'] ?? 0) + (b.value['DIESEL'] ?? 0);

      return bTotal.compareTo(aTotal);
    });

  return entries;
}

List<MapEntry<String, Map<String, int>>> get _fuelingsByOmc {
  final result = <String, Map<String, int>>{};

  for (final row in _fuelings) {
    var omc = _text(row['omc']);
    if (omc.isEmpty) omc = 'Unknown';

    final product = _text(row['fuel_type']).toUpperCase();

    if (product != 'PETROL' && product != 'DIESEL') continue;

    result.putIfAbsent(
      omc,
      () => {
        'PETROL': 0,
        'DIESEL': 0,
      },
    );

    result[omc]![product] =
        (result[omc]![product] ?? 0) + 1;
  }

  final entries = result.entries.toList()
    ..sort((a, b) {
      final aTotal =
          (a.value['PETROL'] ?? 0) + (a.value['DIESEL'] ?? 0);
      final bTotal =
          (b.value['PETROL'] ?? 0) + (b.value['DIESEL'] ?? 0);

      return bTotal.compareTo(aTotal);
    });

  return entries;
}

List<MapEntry<String, Map<String, int>>> get _fuelingsByRegion {
  final result = <String, Map<String, int>>{};

  for (final row in _fuelings) {
    var region = _text(row['region']);
    if (region.isEmpty) region = 'Unknown';

    final product = _text(row['fuel_type']).toUpperCase();

    if (product != 'PETROL' && product != 'DIESEL') continue;

    result.putIfAbsent(
      region,
      () => {
        'PETROL': 0,
        'DIESEL': 0,
      },
    );

    result[region]![product] =
        (result[region]![product] ?? 0) + 1;
  }

  final entries = result.entries.toList()
    ..sort((a, b) {
      final aTotal =
          (a.value['PETROL'] ?? 0) + (a.value['DIESEL'] ?? 0);
      final bTotal =
          (b.value['PETROL'] ?? 0) + (b.value['DIESEL'] ?? 0);

      return bTotal.compareTo(aTotal);
    });

  return entries;
}

  Map<String, double> get _expectedByProduct {
    final result = <String, double>{'PETROL': 0, 'DIESEL': 0, 'PARAFFIN': 0};

    for (final row in _expectedDeliveries) {
      final product = _text(row['product']).toUpperCase();
      result[product] =
          (result[product] ?? 0) + _number(row['quantity_litres']);
    }

    return result;
  }

  List<_RiskRow> get _riskRows {
    final consumption = _consumptionByStationProduct;
    final result = <_RiskRow>[];

    for (final station in _stations) {
      final id = _stationId(station);
      if (id.isEmpty) continue;

      for (final product in ['PETROL', 'DIESEL']) {
        final consumptionRow = consumption['$id|$product'];

        if (consumptionRow == null) continue;

        if (_text(consumptionRow['consumption_data_status']).toUpperCase() !=
            'SUFFICIENT') {
          continue;
        }

        final daily = _number(
          consumptionRow['estimated_daily_consumption_litres'],
        );

        if (daily <= 0) continue;

        final stock = product == 'PETROL'
            ? _number(station['current_petrol_litres'])
            : _number(station['current_diesel_litres']);

        final days = stock / daily;

        result.add(
          _RiskRow(
            station: _stationName(station),
            district: _text(station['district_name']),
            omc: _text(station['omc']),
            product: product,
            stock: stock,
            dailyConsumption: daily,
            daysRemaining: days,
          ),
        );
      }
    }

    result.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    return result;
  }

  String _riskLabel(double days) {
    if (days < 1) return 'CRITICAL';
    if (days < 2) return 'LOW';
    if (days < 3) return 'WATCH';
    return 'ADEQUATE';
  }

  Color _riskColor(double days) {
    if (days < 1) return Colors.red;
    if (days < 2) return Colors.orange;
    if (days < 3) return Colors.amber.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 46,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 14),
              const Text(
                'Unable to load analytics',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadAnalytics,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final petrolDays = _daysRemaining(
      _currentPetrolStock,
      _petrolDailyConsumption,
    );

    final dieselDays = _daysRemaining(
      _currentDieselStock,
      _dieselDailyConsumption,
    );

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              selectedPeriod: _selectedPeriod,
              periods: _periods,
              startDate: _formatDate(_startDate),
              endDate: _formatDate(_endDate),
              onPeriodChanged: _changePeriod,
              onRefresh: _loadAnalytics,
            ),
            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                final columns = width >= 1200
                    ? 6
                    : width >= 800
                    ? 3
                    : width >= 500
                    ? 2
                    : 1;

                final cardWidth = (width - ((columns - 1) * 12)) / columns;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _KpiCard(
                      width: cardWidth,
                      title: 'Fueling Transactions',
                      value: _formatNumber(_totalFuelings),
                      subtitle: _selectedPeriod,
                      icon: Icons.local_gas_station,
                    ),
                    _KpiCard(
                      width: cardWidth,
                      title: 'Unique Vehicles',
                      value: _formatNumber(_uniqueVehicles),
                      subtitle: 'Vehicles / motorcycles',
                      icon: Icons.directions_car_outlined,
                    ),
                    _KpiCard(
                      width: cardWidth,
                      title: 'Active Stations',
                      value: _formatNumber(_activeStations),
                      subtitle: 'Recorded fuelings',
                      icon: Icons.storefront_outlined,
                    ),
                    _KpiCard(
                      width: cardWidth,
                      title: 'Expected Deliveries',
                      value: _formatLitres(_expectedLitres),
                      subtitle: 'Selected period',
                      icon: Icons.local_shipping_outlined,
                    ),
                    _KpiCard(
                      width: cardWidth,
                      title: 'Sync Conflicts',
                      value: _formatNumber(_syncConflicts),
                      subtitle: 'Fueling records',
                      icon: Icons.sync_problem_outlined,
                    ),
                    _KpiCard(
                      width: cardWidth,
                      title: 'Overrides',
                      value: _formatNumber(_overrides),
                      subtitle: 'Fueling controls',
                      icon: Icons.admin_panel_settings_outlined,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            _Panel(
              title: 'Fueling Activity Trend',
              subtitle: 'Fueling transactions by Malawi calendar day',
              child: SizedBox(
                height: 300,
                child: _DailyTrendChart(values: _fuelingsByDay),
              ),
            ),

            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1050;

                final supply = _SupplyConsumptionPanel(
                  petrolStock: _currentPetrolStock,
                  dieselStock: _currentDieselStock,
                  petrolDailyConsumption: _petrolDailyConsumption,
                  dieselDailyConsumption: _dieselDailyConsumption,
                  expectedByProduct: _expectedByProduct,
                  formatLitres: _formatLitres,
                );

                final days = _DaysRemainingPanel(
                  petrolDays: petrolDays,
                  dieselDays: dieselDays,
                  petrolStock: _currentPetrolStock,
                  dieselStock: _currentDieselStock,
                  petrolDailyConsumption: _petrolDailyConsumption,
                  dieselDailyConsumption: _dieselDailyConsumption,
                  formatLitres: _formatLitres,
                  riskLabel: _riskLabel,
                  riskColor: _riskColor,
                );

                if (!wide) {
                  return Column(
                    children: [supply, const SizedBox(height: 22), days],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: supply),
                    const SizedBox(width: 22),
                    Expanded(child: days),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1050;

                final region = _RankingPanel(
                  title: 'Regional Fueling Activity',
                  subtitle: 'Transactions by region',
                  rows: _fuelingsByRegion,
                  emptyText: 'No regional fueling activity.',
                );

                final omc = _RankingPanel(
                  title: 'OMC Fueling Activity',
                  subtitle: 'Transactions by OMC',
                  rows: _fuelingsByOmc,
                  emptyText: 'No OMC fueling activity.',
                );

                if (!wide) {
                  return Column(
                    children: [region, const SizedBox(height: 22), omc],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: region),
                    const SizedBox(width: 22),
                    Expanded(child: omc),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1050;

                final stations = _RankingPanel(
                  title: 'Busiest Filling Stations',
                  subtitle: 'Fueling transactions during selected period',
                  rows: _fuelingsByStation.take(10).toList(),
                  emptyText: 'No station fueling activity.',
                );

                final hourly = _Panel(
                  title: 'Fueling Demand by Hour',
                  subtitle: 'Malawi local time',
                  child: SizedBox(
                    height: 320,
                    child: _HourlyDemandChart(values: _fuelingsByHour),
                  ),
                );

                if (!wide) {
                  return Column(
                    children: [stations, const SizedBox(height: 22), hourly],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: stations),
                    const SizedBox(width: 22),
                    Expanded(child: hourly),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            _ControlAnalyticsPanel(
              totalRejections: _totalRejections,
              syncConflicts: _syncConflicts,
              overrides: _overrides,
              rejections: _rejections,
              formatNumber: _formatNumber,
            ),

            const SizedBox(height: 22),

            _RiskTable(
              rows: _riskRows,
              formatLitres: _formatLitres,
              riskLabel: _riskLabel,
              riskColor: _riskColor,
            ),

            const SizedBox(height: 22),

            _Panel(
              title: 'Expected vs Recorded Supply',
              subtitle:
                  'Expected deliveries are shown for the selected period. '
                  'Recorded receipts currently use the cumulative receipt '
                  'view and are therefore shown separately until a '
                  'period-based receipt analytics view is added.',
              child: _ExpectedRecordedSupply(
                expectedByProduct: _expectedByProduct,
                regionalReceipts: _regionalReceipts,
                formatLitres: _formatLitres,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.selectedPeriod,
    required this.periods,
    required this.startDate,
    required this.endDate,
    required this.onPeriodChanged,
    required this.onRefresh,
  });

  final String selectedPeriod;
  final List<String> periods;
  final String startDate;
  final String endDate;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 850;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analytics',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Fuel supply, demand, consumption and control intelligence',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 4),
            Text(
              startDate == endDate ? startDate : '$startDate - $endDate',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        );

        final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...periods.map(
              (period) => ChoiceChip(
                label: Text(period),
                selected: period == selectedPeriod,
                onSelected: (_) => onPeriodChanged(period),
              ),
            ),
            IconButton.filledTonal(
              onPressed: onRefresh,
              tooltip: 'Refresh analytics',
              icon: const Icon(Icons.refresh),
            ),
          ],
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 16), controls],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            controls,
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006B54).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.analytics_outlined,
                    color: Color(0xFF006B54),
                    size: 21,
                  ),
                ),
                const Spacer(),
                Icon(icon, size: 20, color: Colors.black38),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({required this.values});

  final Map<DateTime, Map<String, int>> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(
        child: Text('No fueling trend data available.'),
      );
    }

    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final petrolSpots = <FlSpot>[];
    final dieselSpots = <FlSpot>[];

    var maxValue = 0;

    for (var i = 0; i < entries.length; i++) {
      final petrol = entries[i].value['PETROL'] ?? 0;
      final diesel = entries[i].value['DIESEL'] ?? 0;

      petrolSpots.add(
        FlSpot(i.toDouble(), petrol.toDouble()),
      );

      dieselSpots.add(
        FlSpot(i.toDouble(), diesel.toDouble()),
      );

      maxValue = math.max(
        maxValue,
        math.max(petrol, diesel),
      );
    }

    const petrolColor = Color(0xFF18A94B);
    const dieselColor = Color(0xFFF4B41A);

    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ChartLegendItem(
              color: petrolColor,
              label: 'Petrol',
            ),
            SizedBox(width: 20),
            _ChartLegendItem(
              color: dieselColor,
              label: 'Diesel',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: math.max(5, maxValue * 1.2).toDouble(),
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: entries.length > 30
                        ? 10
                        : entries.length > 10
                            ? 5
                            : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();

                      if (index < 0 || index >= entries.length) {
                        return const SizedBox.shrink();
                      }

                      final date = entries[index].key;

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${date.day}/${date.month}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x.round();

                      if (index < 0 || index >= entries.length) {
                        return null;
                      }

                      final date = entries[index].key;
                      final product =
                          spot.barIndex == 0 ? 'Petrol' : 'Diesel';

                      return LineTooltipItem(
                        '$product\n'
                        '${date.day}/${date.month}: '
                        '${spot.y.toInt()} transactions',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: petrolSpots,
                  isCurved: true,
                  barWidth: 3,
                  color: petrolColor,
                  dotData: FlDotData(
                    show: entries.length <= 14,
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: petrolColor.withValues(alpha: 0.06),
                  ),
                ),
                LineChartBarData(
                  spots: dieselSpots,
                  isCurved: true,
                  barWidth: 3,
                  color: dieselColor,
                  dotData: FlDotData(
                    show: entries.length <= 14,
                  ),
                  belowBarData: BarAreaData(
                    show: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _HourlyDemandChart extends StatelessWidget {
  const _HourlyDemandChart({required this.values});

  final Map<int, Map<String, int>> values;

  @override
  Widget build(BuildContext context) {
    var maxValue = 0;

    for (final value in values.values) {
      maxValue = math.max(maxValue, value['PETROL'] ?? 0);
      maxValue = math.max(maxValue, value['DIESEL'] ?? 0);
    }

    const petrolColor = Color(0xFF18A94B);
    const dieselColor = Color(0xFFF4B41A);

    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ChartLegendItem(
              color: petrolColor,
              label: 'Petrol',
            ),
            SizedBox(width: 18),
            _ChartLegendItem(
              color: dieselColor,
              label: 'Diesel',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: math.max(5, maxValue * 1.2).toDouble(),
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final hour = value.toInt();

                      if (hour % 3 != 0) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          hour.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final product = rodIndex == 0 ? 'Petrol' : 'Diesel';
                    final hour =
                        group.x.toString().padLeft(2, '0');

                    return BarTooltipItem(
                      '$product\n$hour:00\n${rod.toY.toInt()} transactions',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var hour = 0; hour < 24; hour++)
                  BarChartGroupData(
                    x: hour,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY:
                            (values[hour]?['PETROL'] ?? 0).toDouble(),
                        width: 6,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        color: petrolColor,
                      ),
                      BarChartRodData(
                        toY:
                            (values[hour]?['DIESEL'] ?? 0).toDouble(),
                        width: 6,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        color: dieselColor,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplyConsumptionPanel extends StatelessWidget {
  const _SupplyConsumptionPanel({
    required this.petrolStock,
    required this.dieselStock,
    required this.petrolDailyConsumption,
    required this.dieselDailyConsumption,
    required this.expectedByProduct,
    required this.formatLitres,
  });

  final double petrolStock;
  final double dieselStock;
  final double petrolDailyConsumption;
  final double dieselDailyConsumption;
  final Map<String, double> expectedByProduct;
  final String Function(double) formatLitres;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Supply & Consumption',
      subtitle:
          'Current physical stock, estimated daily consumption and expected supply',
      child: Column(
        children: [
          _SupplyRow(
            product: 'Petrol',
            stock: petrolStock,
            dailyConsumption: petrolDailyConsumption,
            expected: expectedByProduct['PETROL'] ?? 0,
            formatLitres: formatLitres,
          ),
          const Divider(height: 28),
          _SupplyRow(
            product: 'Diesel',
            stock: dieselStock,
            dailyConsumption: dieselDailyConsumption,
            expected: expectedByProduct['DIESEL'] ?? 0,
            formatLitres: formatLitres,
          ),
        ],
      ),
    );
  }
}

class _SupplyRow extends StatelessWidget {
  const _SupplyRow({
    required this.product,
    required this.stock,
    required this.dailyConsumption,
    required this.expected,
    required this.formatLitres,
  });

  final String product;
  final double stock;
  final double dailyConsumption;
  final double expected;
  final String Function(double) formatLitres;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            product,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          flex: 3,
          child: _Metric(label: 'Current Stock', value: formatLitres(stock)),
        ),
        Expanded(
          flex: 3,
          child: _Metric(
            label: 'Est. Daily Use',
            value: dailyConsumption > 0
                ? formatLitres(dailyConsumption)
                : 'Insufficient data',
          ),
        ),
        Expanded(
          flex: 3,
          child: _Metric(label: 'Expected', value: formatLitres(expected)),
        ),
      ],
    );
  }
}

class _DaysRemainingPanel extends StatelessWidget {
  const _DaysRemainingPanel({
    required this.petrolDays,
    required this.dieselDays,
    required this.petrolStock,
    required this.dieselStock,
    required this.petrolDailyConsumption,
    required this.dieselDailyConsumption,
    required this.formatLitres,
    required this.riskLabel,
    required this.riskColor,
  });

  final double? petrolDays;
  final double? dieselDays;
  final double petrolStock;
  final double dieselStock;
  final double petrolDailyConsumption;
  final double dieselDailyConsumption;
  final String Function(double) formatLitres;
  final String Function(double) riskLabel;
  final Color Function(double) riskColor;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Estimated Days of Stock',
      subtitle: 'Current stock divided by estimated daily consumption',
      child: Column(
        children: [
          _DaysRow(
            product: 'Petrol',
            days: petrolDays,
            stock: petrolStock,
            dailyConsumption: petrolDailyConsumption,
            formatLitres: formatLitres,
            riskLabel: riskLabel,
            riskColor: riskColor,
          ),
          const Divider(height: 28),
          _DaysRow(
            product: 'Diesel',
            days: dieselDays,
            stock: dieselStock,
            dailyConsumption: dieselDailyConsumption,
            formatLitres: formatLitres,
            riskLabel: riskLabel,
            riskColor: riskColor,
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Risk guide: Critical <1 day • Low <2 days • '
              'Watch <3 days • Adequate ≥3 days',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaysRow extends StatelessWidget {
  const _DaysRow({
    required this.product,
    required this.days,
    required this.stock,
    required this.dailyConsumption,
    required this.formatLitres,
    required this.riskLabel,
    required this.riskColor,
  });

  final String product;
  final double? days;
  final double stock;
  final double dailyConsumption;
  final String Function(double) formatLitres;
  final String Function(double) riskLabel;
  final Color Function(double) riskColor;

  @override
  Widget build(BuildContext context) {
    final value = days;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatLitres(stock)} stock',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                dailyConsumption > 0
                    ? '${formatLitres(dailyConsumption)} / day'
                    : 'Insufficient consumption data',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (value == null)
          const Text(
            'Insufficient Data',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${value.toStringAsFixed(1)} days',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor(value).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  riskLabel(value),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: riskColor(value),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _RankingPanel extends StatelessWidget {
  const _RankingPanel({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.emptyText,
  });

  final String title;
  final String subtitle;
  final List<MapEntry<String, Map<String, int>>> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    var maxValue = 1;

    for (final row in rows) {
      final total =
          (row.value['PETROL'] ?? 0) + (row.value['DIESEL'] ?? 0);
      maxValue = math.max(maxValue, total);
    }

    const petrolColor = Color(0xFF18A94B);
    const dieselColor = Color(0xFFF4B41A);

    return _Panel(
      title: title,
      subtitle: subtitle,
      child: rows.isEmpty
          ? SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  emptyText,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            )
          : Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ChartLegendItem(
                      color: petrolColor,
                      label: 'Petrol',
                    ),
                    SizedBox(width: 18),
                    _ChartLegendItem(
                      color: dieselColor,
                      label: 'Diesel',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...rows.take(10).map((row) {
                  final petrol = row.value['PETROL'] ?? 0;
                  final diesel = row.value['DIESEL'] ?? 0;
                  final total = petrol + diesel;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Total $total',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            const SizedBox(
                              width: 44,
                              child: Text(
                                'Petrol',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: petrol / maxValue,
                                  backgroundColor: Colors.black12,
                                  color: petrolColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 35,
                              child: Text(
                                '$petrol',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const SizedBox(
                              width: 44,
                              child: Text(
                                'Diesel',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: diesel / maxValue,
                                  backgroundColor: Colors.black12,
                                  color: dieselColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 35,
                              child: Text(
                                '$diesel',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _ControlAnalyticsPanel extends StatelessWidget {
  const _ControlAnalyticsPanel({
    required this.totalRejections,
    required this.syncConflicts,
    required this.overrides,
    required this.rejections,
    required this.formatNumber,
  });

  final int totalRejections;
  final int syncConflicts;
  final int overrides;
  final List<Map<String, dynamic>> rejections;
  final String Function(num) formatNumber;

  int _integer(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final alreadyFueled = rejections.fold<int>(
      0,
      (sum, row) => sum + _integer(row['already_fueled_count']),
    );

    final identifierConflicts = rejections.fold<int>(
      0,
      (sum, row) => sum + _integer(row['identifier_conflict_count']),
    );

    final invalid = rejections.fold<int>(
      0,
      (sum, row) => sum + _integer(row['invalid_count']),
    );

    return _Panel(
      title: 'Fuel Control & Exception Analytics',
      subtitle:
          'Restriction enforcement, rejection cases, overrides and synchronization exceptions',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SmallStat(
            label: 'Total Rejections',
            value: formatNumber(totalRejections),
          ),
          _SmallStat(
            label: 'Already Fueled',
            value: formatNumber(alreadyFueled),
          ),
          _SmallStat(
            label: 'Identifier Conflicts',
            value: formatNumber(identifierConflicts),
          ),
          _SmallStat(label: 'Invalid Attempts', value: formatNumber(invalid)),
          _SmallStat(
            label: 'Sync Conflicts',
            value: formatNumber(syncConflicts),
          ),
          _SmallStat(label: 'Overrides', value: formatNumber(overrides)),
        ],
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _RiskRow {
  const _RiskRow({
    required this.station,
    required this.district,
    required this.omc,
    required this.product,
    required this.stock,
    required this.dailyConsumption,
    required this.daysRemaining,
  });

  final String station;
  final String district;
  final String omc;
  final String product;
  final double stock;
  final double dailyConsumption;
  final double daysRemaining;
}

class _RiskTable extends StatelessWidget {
  const _RiskTable({
    required this.rows,
    required this.formatLitres,
    required this.riskLabel,
    required this.riskColor,
  });

  final List<_RiskRow> rows;
  final String Function(double) formatLitres;
  final String Function(double) riskLabel;
  final Color Function(double) riskColor;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.take(25).toList();

    return _Panel(
      title: 'Stations at Supply Risk',
      subtitle:
          'Projection based on current stock and sufficient observed consumption data',
      child: visibleRows.isEmpty
          ? const SizedBox(
              height: 150,
              child: Center(
                child: Text(
                  'Insufficient consumption data for supply-risk projection.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1050,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.4),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.0),
                    4: FlexColumnWidth(1.3),
                    5: FlexColumnWidth(1.4),
                    6: FlexColumnWidth(1.1),
                    7: FlexColumnWidth(1.1),
                  },
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: Colors.black12),
                  ),
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFF4F7F6)),
                      children: [
                        _TH('Station'),
                        _TH('District'),
                        _TH('OMC'),
                        _TH('Product'),
                        _TH('Current Stock'),
                        _TH('Est. L/day'),
                        _TH('Days Left'),
                        _TH('Risk'),
                      ],
                    ),
                    ...visibleRows.map(
                      (row) => TableRow(
                        children: [
                          _TD(row.station),
                          _TD(row.district),
                          _TD(row.omc),
                          _TD(row.product),
                          _TD(formatLitres(row.stock), right: true),
                          _TD(formatLitres(row.dailyConsumption), right: true),
                          _TD(
                            row.daysRemaining.toStringAsFixed(1),
                            right: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: riskColor(
                                    row.daysRemaining,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  riskLabel(row.daysRemaining),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: riskColor(row.daysRemaining),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ExpectedRecordedSupply extends StatelessWidget {
  const _ExpectedRecordedSupply({
    required this.expectedByProduct,
    required this.regionalReceipts,
    required this.formatLitres,
  });

  final Map<String, double> expectedByProduct;
  final List<Map<String, dynamic>> regionalReceipts;
  final String Function(double) formatLitres;

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _text(dynamic value) {
    return value?.toString().trim().toUpperCase() ?? '';
  }

  double _recorded(String product) {
    return regionalReceipts
        .where((row) => _text(row['product']) == product)
        .fold(0, (sum, row) => sum + _number(row['total_received_litres']));
  }

  @override
  Widget build(BuildContext context) {
    final petrolRecorded = _recorded('PETROL');
    final dieselRecorded = _recorded('DIESEL');

    return Column(
      children: [
        _SupplyComparisonRow(
          product: 'Petrol',
          expected: expectedByProduct['PETROL'] ?? 0,
          recorded: petrolRecorded,
          formatLitres: formatLitres,
        ),
        const Divider(height: 28),
        _SupplyComparisonRow(
          product: 'Diesel',
          expected: expectedByProduct['DIESEL'] ?? 0,
          recorded: dieselRecorded,
          formatLitres: formatLitres,
        ),
      ],
    );
  }
}

class _SupplyComparisonRow extends StatelessWidget {
  const _SupplyComparisonRow({
    required this.product,
    required this.expected,
    required this.recorded,
    required this.formatLitres,
  });

  final String product;
  final double expected;
  final double recorded;
  final String Function(double) formatLitres;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            product,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          flex: 3,
          child: _Metric(
            label: 'Expected - selected period',
            value: formatLitres(expected),
          ),
        ),
        Expanded(
          flex: 3,
          child: _Metric(
            label: 'Recorded receipts - cumulative',
            value: formatLitres(recorded),
          ),
        ),
      ],
    );
  }
}

class _TH extends StatelessWidget {
  const _TH(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TD extends StatelessWidget {
  const _TD(this.text, {this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text.isEmpty ? '-' : text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
