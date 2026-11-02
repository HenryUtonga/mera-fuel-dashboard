import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/dashboard_service.dart';

class ExpectedDeliveriesPage extends StatefulWidget {
  const ExpectedDeliveriesPage({super.key});

  @override
  State<ExpectedDeliveriesPage> createState() => _ExpectedDeliveriesPageState();
}

class _ExpectedDeliveriesPageState extends State<ExpectedDeliveriesPage> {
  final DashboardService _dashboardService = DashboardService();

  late Future<List<Map<String, dynamic>>> _deliveriesFuture;

  DateTime _selectedDate = DateTime.now();

  String _selectedRegion = 'All';
  String _selectedOmc = 'All';
  String _selectedProduct = 'All';
  String _selectedDistrict = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
  }

  void _loadDeliveries() {
    _deliveriesFuture = _dashboardService.getExpectedDeliveries(
      date: _selectedDate,
    );
  }

  Future<void> _refresh() async {
    setState(_loadDeliveries);
    await _deliveriesFuture;
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );
      _resetFilters();
      _loadDeliveries();
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _resetFilters();
      _loadDeliveries();
    });
  }

  void _resetFilters() {
    _selectedRegion = 'All';
    _selectedOmc = 'All';
    _selectedProduct = 'All';
    _selectedDistrict = 'All';
    _searchQuery = '';
  }

  void _clearFilters() {
    setState(_resetFilters);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _deliveriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load expected deliveries: ${snapshot.error}',
              ),
            ),
          );
        }

        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];

        final regions = _uniqueValues(allRows, 'region');
        final omcs = _uniqueValues(allRows, 'omc');
        final districts = _uniqueValues(allRows, 'district_name');

        final filteredRows = allRows.where((row) {
          if (_selectedRegion != 'All' &&
              _value(row, 'region') != _selectedRegion) {
            return false;
          }

          if (_selectedOmc != 'All' && _value(row, 'omc') != _selectedOmc) {
            return false;
          }

          if (_selectedProduct != 'All' &&
              _value(row, 'product').toUpperCase() != _selectedProduct) {
            return false;
          }

          if (_selectedDistrict != 'All' &&
              _value(row, 'district_name') != _selectedDistrict) {
            return false;
          }

          final query = _searchQuery.trim().toLowerCase();

          if (query.isNotEmpty) {
            final station = _value(row, 'filling_station_name').toLowerCase();
            final district = _value(row, 'district_name').toLowerCase();
            final omc = _value(row, 'omc').toLowerCase();

            if (!station.contains(query) &&
                !district.contains(query) &&
                !omc.contains(query)) {
              return false;
            }
          }

          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      selectedDate: _selectedDate,
                      onPrevious: () => _changeDate(-1),
                      onNext: () => _changeDate(1),
                      onToday: _goToToday,
                      onRefresh: _refresh,
                    ),
                    const SizedBox(height: 22),
                    _SummaryCards(rows: filteredRows),
                    const SizedBox(height: 20),
                    _FiltersPanel(
                      regions: regions,
                      omcs: omcs,
                      districts: districts,
                      selectedRegion: _selectedRegion,
                      selectedOmc: _selectedOmc,
                      selectedProduct: _selectedProduct,
                      selectedDistrict: _selectedDistrict,
                      searchQuery: _searchQuery,
                      onRegionChanged: (value) {
                        setState(() {
                          _selectedRegion = value ?? 'All';
                        });
                      },
                      onOmcChanged: (value) {
                        setState(() {
                          _selectedOmc = value ?? 'All';
                        });
                      },
                      onProductChanged: (value) {
                        setState(() {
                          _selectedProduct = value ?? 'All';
                        });
                      },
                      onDistrictChanged: (value) {
                        setState(() {
                          _selectedDistrict = value ?? 'All';
                        });
                      },
                      onSearchChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      onClear: _clearFilters,
                    ),
                    const SizedBox(height: 20),
                    _Breakdowns(rows: filteredRows),
                    const SizedBox(height: 20),
                    _MapAndTable(rows: filteredRows),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.selectedDate,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onRefresh,
  });

  final DateTime selectedDate;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expected Deliveries',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Expected fuel distribution for ${_formatDate(selectedDate)}',
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        );

        final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: 'Previous day',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              onPressed: onToday,
              icon: const Icon(Icons.today_outlined),
              label: const Text('Today'),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                _formatShortDate(selectedDate),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Next day',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => onRefresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        );

        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 16), controls],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            controls,
          ],
        );
      },
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final total = _totalLitres(rows);

    final petrolRows = rows.where((row) => _product(row) == 'PETROL');

    final dieselRows = rows.where((row) => _product(row) == 'DIESEL');

    final petrol = petrolRows.fold<double>(
      0,
      (total, row) => total + _quantity(row),
    );

    final diesel = dieselRows.fold<double>(
      0,
      (total, row) => total + _quantity(row),
    );

    final stations = rows
        .map((row) => _value(row, 'filling_station_id'))
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;

    final cards = [
      _CardData(
        title: 'Total Expected',
        value: '${_formatLitres(total)} L',
        subtitle: '${rows.length} delivery records',
        icon: Icons.local_shipping_outlined,
        background: const Color(0xFFD9EAD3),
        accent: const Color(0xFF38761D),
      ),
      _CardData(
        title: 'Petrol Expected',
        value: '${_formatLitres(petrol)} L',
        subtitle: '${petrolRows.length} delivery records',
        icon: Icons.water_drop,
        background: const Color(0xFFB7EAF3),
        accent: const Color(0xFF007C91),
      ),
      _CardData(
        title: 'Diesel Expected',
        value: '${_formatLitres(diesel)} L',
        subtitle: '${dieselRows.length} delivery records',
        icon: Icons.opacity,
        background: const Color(0xFFFCE8A6),
        accent: const Color(0xFF8A6500),
      ),
      _CardData(
        title: 'Stations Receiving',
        value: '$stations',
        subtitle: 'Unique filling stations',
        icon: Icons.location_on_outlined,
        background: const Color(0xFFE8E0F5),
        accent: const Color(0xFF65449A),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final cardWidth = width >= 1100
            ? (width - 48) / 4
            : width >= 600
            ? (width - 16) / 2
            : width;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((data) {
            return SizedBox(
              width: cardWidth,
              height: 145,
              child: _SummaryCard(data: data),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final _CardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: data.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    color: data.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.regions,
    required this.omcs,
    required this.districts,
    required this.selectedRegion,
    required this.selectedOmc,
    required this.selectedProduct,
    required this.selectedDistrict,
    required this.searchQuery,
    required this.onRegionChanged,
    required this.onOmcChanged,
    required this.onProductChanged,
    required this.onDistrictChanged,
    required this.onSearchChanged,
    required this.onClear,
  });

  final List<String> regions;
  final List<String> omcs;
  final List<String> districts;

  final String selectedRegion;
  final String selectedOmc;
  final String selectedProduct;
  final String selectedDistrict;
  final String searchQuery;

  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<String?> onOmcChanged;
  final ValueChanged<String?> onProductChanged;
  final ValueChanged<String?> onDistrictChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Filter Expected Deliveries',
      subtitle:
          'Filter the entire dashboard by geography, OMC, product or station',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              final fieldWidth = width >= 1000
                  ? (width - 48) / 4
                  : width >= 600
                  ? (width - 16) / 2
                  : width;

              return Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _DropdownFilter(
                      label: 'Region',
                      value: selectedRegion,
                      values: ['All', ...regions],
                      onChanged: onRegionChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _DropdownFilter(
                      label: 'OMC',
                      value: selectedOmc,
                      values: ['All', ...omcs],
                      onChanged: onOmcChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _DropdownFilter(
                      label: 'Product',
                      value: selectedProduct,
                      values: const ['All', 'PETROL', 'DIESEL'],
                      onChanged: onProductChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _DropdownFilter(
                      label: 'District',
                      value: selectedDistrict,
                      values: ['All', ...districts],
                      onChanged: onDistrictChanged,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: searchQuery)
                    ..selection = TextSelection.collapsed(
                      offset: searchQuery.length,
                    ),
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search station, district or OMC...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFFF4F7F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : 'All',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF4F7F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: values.map((item) {
        return DropdownMenuItem(value: item, child: Text(item));
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _Breakdowns extends StatelessWidget {
  const _Breakdowns({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final omcTotals = _groupTotals(rows, 'omc');
    final regionTotals = _groupTotals(rows, 'region');

    final petrol = rows
        .where((row) => _product(row) == 'PETROL')
        .fold<double>(0, (total, row) => total + _quantity(row));

    final diesel = rows
        .where((row) => _product(row) == 'DIESEL')
        .fold<double>(0, (total, row) => total + _quantity(row));

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = [
          _BreakdownCard(
            title: 'Expected Fuel by OMC',
            subtitle: 'Litres allocated by oil marketing company',
            totals: omcTotals,
          ),
          _BreakdownCard(
            title: 'Expected Fuel by Region',
            subtitle: 'Expected litres by Malawi region',
            totals: regionTotals,
          ),
          _ProductChart(petrol: petrol, diesel: diesel),
        ];

        if (constraints.maxWidth < 1050) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 16),
            Expanded(child: children[1]),
            const SizedBox(width: 16),
            Expanded(child: children[2]),
          ],
        );
      },
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.subtitle,
    required this.totals,
  });

  final String title;
  final String subtitle;
  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maximum = entries.isEmpty
        ? 1.0
        : entries.first.value == 0
        ? 1.0
        : entries.first.value;

    return _Panel(
      title: title,
      subtitle: subtitle,
      child: SizedBox(
        height: 230,
        child: entries.isEmpty
            ? const Center(
                child: Text(
                  'No delivery data',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 13),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final progress = entry.value / maximum;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatLitres(entry.value)} L',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(10),
                        backgroundColor: const Color(0xFFE8EEEC),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _ProductChart extends StatelessWidget {
  const _ProductChart({required this.petrol, required this.diesel});

  final double petrol;
  final double diesel;

  @override
  Widget build(BuildContext context) {
    final total = petrol + diesel;

    return _Panel(
      title: 'Product Mix',
      subtitle: 'Petrol versus diesel expected today',
      child: SizedBox(
        height: 230,
        child: total == 0
            ? const Center(
                child: Text(
                  'No delivery data',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 38,
                        sectionsSpace: 3,
                        sections: [
                          PieChartSectionData(
                            value: petrol,
                            title: '${((petrol / total) * 100).round()}%',
                            radius: 58,
                            color: const Color(0xFF007C91),
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          PieChartSectionData(
                            value: diesel,
                            title: '${((diesel / total) * 100).round()}%',
                            radius: 58,
                            color: const Color(0xFF8A6500),
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProductLegend(
                        color: const Color(0xFF007C91),
                        label: 'Petrol',
                        litres: petrol,
                      ),
                      const SizedBox(height: 16),
                      _ProductLegend(
                        color: const Color(0xFF8A6500),
                        label: 'Diesel',
                        litres: diesel,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProductLegend extends StatelessWidget {
  const _ProductLegend({
    required this.color,
    required this.label,
    required this.litres,
  });

  final Color color;
  final String label;
  final double litres;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              '${_formatLitres(litres)} L',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapAndTable extends StatelessWidget {
  const _MapAndTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return Column(
            children: [
              _ExpectedMap(rows: rows),
              const SizedBox(height: 20),
              _DeliveryTable(rows: rows),
            ],
          );
        }

        return SizedBox(
          height: 610,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: _ExpectedMap(rows: rows)),
              const SizedBox(width: 20),
              Expanded(flex: 7, child: _DeliveryTable(rows: rows)),
            ],
          ),
        );
      },
    );
  }
}

class _ExpectedMap extends StatelessWidget {
  const _ExpectedMap({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final mappableRows = rows.where((row) {
      return row['latitude'] is num && row['longitude'] is num;
    }).toList();

    final markers = mappableRows.map((row) {
      final latitude = (row['latitude'] as num).toDouble();
      final longitude = (row['longitude'] as num).toDouble();

      final product = _product(row);
      final color = product == 'PETROL'
          ? const Color(0xFF007C91)
          : const Color(0xFF8A6500);

      return Marker(
        point: LatLng(latitude, longitude),
        width: 38,
        height: 38,
        child: Tooltip(
          message:
              '${_value(row, 'filling_station_name')}\n'
              '${_value(row, 'omc')}\n'
              '$product • ${_formatLitres(_quantity(row))} L\n'
              '${_formatTime(row['expected_delivery_at'])}',
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(
              Icons.local_shipping,
              color: Colors.white,
              size: 19,
            ),
          ),
        ),
      );
    }).toList();

    return _Panel(
      title: 'Expected Delivery Map',
      subtitle: '${mappableRows.length} delivery records mapped',
      child: SizedBox(
        height: 500,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-13.2543, 34.3015),
              initialZoom: 6.2,
              minZoom: 5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'mw.mera.fuel_dashboard',
              ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryTable extends StatelessWidget {
  const _DeliveryTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Stations Receiving Fuel',
      subtitle: '${rows.length} delivery records',
      child: SizedBox(
        height: 500,
        child: rows.isEmpty
            ? const Center(
                child: Text(
                  'No expected deliveries for the selected filters.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 780,
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.4),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.0),
                        3: FlexColumnWidth(1.4),
                        4: FlexColumnWidth(1.0),
                        5: FlexColumnWidth(1.3),
                        6: FlexColumnWidth(1.2),
                      },
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: Colors.black12),
                      ),
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFFF4F7F6)),
                          children: [
                            _TableHeader('Station'),
                            _TableHeader('District'),
                            _TableHeader('Region'),
                            _TableHeader('OMC'),
                            _TableHeader('Product'),
                            _TableHeader('Expected'),
                            _TableHeader('Time'),
                          ],
                        ),
                        ...rows.map(
                          (row) => TableRow(
                            children: [
                              _TableCell(_value(row, 'filling_station_name')),
                              _TableCell(_value(row, 'district_name')),
                              _TableCell(_value(row, 'region')),
                              _TableCell(_value(row, 'omc')),
                              _TableCell(_product(row)),
                              _TableCell(
                                '${_formatLitres(_quantity(row))} L',
                                right: true,
                              ),
                              _TableCell(
                                _formatTime(row['expected_delivery_at']),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.text, {this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      child: Text(
        text.isEmpty ? '-' : text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _CardData {
  const _CardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color accent;
}

List<String> _uniqueValues(List<Map<String, dynamic>> rows, String field) {
  final values = rows
      .map((row) => _value(row, field))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  values.sort();

  return values;
}

Map<String, double> _groupTotals(
  List<Map<String, dynamic>> rows,
  String field,
) {
  final totals = <String, double>{};

  for (final row in rows) {
    final key = _value(row, field);

    if (key.isEmpty) {
      continue;
    }

    totals[key] = (totals[key] ?? 0) + _quantity(row);
  }

  return totals;
}

double _totalLitres(Iterable<Map<String, dynamic>> rows) {
  return rows.fold<double>(0, (total, row) => total + _quantity(row));
}

double _quantity(Map<String, dynamic> row) {
  return (row['quantity_litres'] as num?)?.toDouble() ?? 0;
}

String _product(Map<String, dynamic> row) {
  return _value(row, 'product').toUpperCase();
}

String _value(Map<String, dynamic> row, String key) {
  return row[key]?.toString().trim() ?? '';
}

String _formatLitres(double value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < rounded.length; i++) {
    final positionFromEnd = rounded.length - i;

    buffer.write(rounded[i]);

    if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

String _formatDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _formatShortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');

  return '$day/$month/${date.year}';
}

String _formatTime(dynamic value) {
  if (value == null) {
    return '-';
  }

  final parsed = DateTime.tryParse(value.toString());

  if (parsed == null) {
    return '-';
  }

  // Convert stored timestamp to Malawi time (UTC+2).
  final malawiTime = parsed.toUtc().add(const Duration(hours: 2));

  final hour = malawiTime.hour.toString().padLeft(2, '0');
  final minute = malawiTime.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}
