import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/mera_theme.dart';

enum OverviewFilter { all, petrol, diesel, lowStock }

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final DashboardService _dashboardService = DashboardService();

  late Future<List<Map<String, dynamic>>> _fuelStatusFuture;

  OverviewFilter _selectedFilter = OverviewFilter.all;

  @override
  void initState() {
    super.initState();
    _fuelStatusFuture = _dashboardService.getStationFuelStatus();
  }

  void _selectFilter(OverviewFilter filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _fuelStatusFuture = _dashboardService.getStationFuelStatus();
    });

    await _fuelStatusFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fuelStatusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unable to load fuel dashboard: ${snapshot.error}'),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        return RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: _OverviewContent(
                  rows: rows,
                  selectedFilter: _selectedFilter,
                  onFilterSelected: _selectFilter,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.rows,
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  final List<Map<String, dynamic>> rows;
  final OverviewFilter selectedFilter;
  final ValueChanged<OverviewFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    final petrolRows = _rowsForProduct(rows, 'PETROL');
    final dieselRows = _rowsForProduct(rows, 'DIESEL');

    final petrolStock = _totalStock(petrolRows);
    final dieselStock = _totalStock(dieselRows);
    final combinedStock = petrolStock + dieselStock;

    final petrolReporting = _reportingStations(petrolRows);
    final dieselReporting = _reportingStations(dieselRows);

    final filteredRows = _applyFilter(rows, selectedFilter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 24),

        _OverviewTopSection(
          rows: filteredRows,
          cards: [
            _OverviewCardData(
              title: 'Fuel Stocks',
              value: '${_formatLitres(combinedStock)} L',
              subtitle:
                  'Petrol ${_formatLitres(petrolStock)} L  •  '
                  'Diesel ${_formatLitres(dieselStock)} L',
              icon: Icons.local_gas_station,
              backgroundColor: MeraColors.paleGreen,
              accentColor: MeraColors.darkGreen,
              filter: OverviewFilter.all,
            ),
            _OverviewCardData(
              title: 'Petrol Stocks',
              value: '${_formatLitres(petrolStock)} L',
              subtitle: '$petrolReporting stations reporting',
              icon: Icons.water_drop,
              backgroundColor: const Color(0xFFEAF5F0),
              accentColor: MeraColors.green,
              filter: OverviewFilter.petrol,
            ),
            _OverviewCardData(
              title: 'Diesel Stocks',
              value: '${_formatLitres(dieselStock)} L',
              subtitle: '$dieselReporting stations reporting',
              icon: Icons.opacity,
              backgroundColor: const Color(0xFFFFF6DD),
              accentColor: const Color(0xFF9A6B00),
              filter: OverviewFilter.diesel,
            ),
          ],
          selectedFilter: selectedFilter,
          onFilterSelected: onFilterSelected,
          table: _StationTablePlaceholder(
            rows: filteredRows,
            selectedFilter: selectedFilter,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
Text(
  'Fuel Dashboard – Overview',
  style: TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: MeraColors.darkGreen,
  ),
),
              SizedBox(height: 6),
Text(
  'National fuel stock availability and station monitoring',
  style: TextStyle(
    fontSize: 15,
    color: MeraColors.mutedText,
  ),
),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: () {
            // Refresh is handled by pull-to-refresh for now.
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _OverviewTopSection extends StatelessWidget {
  const _OverviewTopSection({
    required this.rows,
    required this.cards,
    required this.selectedFilter,
    required this.onFilterSelected,
    required this.table,
  });

  final List<Map<String, dynamic>> rows;
  final List<_OverviewCardData> cards;
  final OverviewFilter selectedFilter;
  final ValueChanged<OverviewFilter> onFilterSelected;
  final Widget table;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return Column(
            children: [
              _CardsGrid(
                cards: cards,
                selectedFilter: selectedFilter,
                onFilterSelected: onFilterSelected,
              ),
              const SizedBox(height: 20),
              _MapPlaceholder(rows: rows, selectedFilter: selectedFilter),
              const SizedBox(height: 20),
              table,
            ],
          );
        }

        return SizedBox(
          height: 900,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _CardsGrid(
                      cards: cards,
                      selectedFilter: selectedFilter,
                      onFilterSelected: onFilterSelected,
                    ),
                    const SizedBox(height: 20),
                    Expanded(child: table),
                  ],
                ),
              ),
              const SizedBox(width: 20),
Expanded(
  flex: 6,
  child: _MapPlaceholder(
    rows: rows,
    selectedFilter: selectedFilter,
    mapHeight: 750,
  ),
),
            ],
          ),
        );
      },
    );
  }
}

class _CardsGrid extends StatelessWidget {
  const _CardsGrid({
    required this.cards,
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  final List<_OverviewCardData> cards;
  final OverviewFilter selectedFilter;
  final ValueChanged<OverviewFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 600
            ? constraints.maxWidth
            : (constraints.maxWidth - 14) / 2;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              height: 175,
              child: _OverviewCard(
                data: card,
                selected: selectedFilter == card.filter,
                onTap: () => onFilterSelected(card.filter),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _OverviewCardData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: data.backgroundColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? data.accentColor
                  : data.accentColor.withValues(alpha: 0.18),
              width: selected ? 3 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, color: data.accentColor),
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle, color: data.accentColor),
                ],
              ),
              const Spacer(),
              Text(
                data.title,
                style: TextStyle(
                  color: data.accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPlaceholder extends StatefulWidget {
  const _MapPlaceholder({
    required this.rows,
    required this.selectedFilter,
    this.mapHeight = 320,
  });

  final List<Map<String, dynamic>> rows;
  final OverviewFilter selectedFilter;
  final double mapHeight;

  @override
  State<_MapPlaceholder> createState() => _MapPlaceholderState();
}

class _MapPlaceholderState extends State<_MapPlaceholder> {
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      setState(() {
        _mapReady = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mappableRows = widget.rows.where((row) {
      final status = _status(row);

      return row['latitude'] != null &&
          row['longitude'] != null &&
          status != 'NO_DATA' &&
          status != 'LOW_STOCK';
    }).toList();
    final markers = mappableRows.map((row) {
      final latitude = (row['latitude'] as num).toDouble();
      final longitude = (row['longitude'] as num).toDouble();

      return Marker(
        point: LatLng(latitude, longitude),
        width: 28,
        height: 28,
        child: Tooltip(
          message:
              '${row['filling_station_name'] ?? 'Unknown Station'}\n'
              '${row['product'] ?? ''}\n'
              '${row['stock_status'] ?? 'NO_DATA'}',
          child: Container(
            decoration: BoxDecoration(
              color: _markerColor(row),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
            child: const Icon(
              Icons.local_gas_station,
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      );
    }).toList();

    return Container(
      constraints: const BoxConstraints(minHeight: 364),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Malawi Fuel Availability',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  '${mappableRows.length} station/product records mapped',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                const _StatusLegend(),
              ],
            ),
          ),

SizedBox(
  height: widget.mapHeight,
  child: _mapReady
      ? FlutterMap(
          
options: MapOptions(
  initialCenter: const LatLng(-13.25, 34.30),
  initialZoom: 6.8,
  minZoom: 6.0,
  maxZoom: 18.0,
),

          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'mw.mera.fuelcontrol',
            ),
            MarkerLayer(
              markers: markers,
            ),
          ],
        )
      : Container(
          alignment: Alignment.center,
          color: MeraColors.background,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text(
                'Loading fuel availability map...',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MeraColors.darkGreen,
                ),
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

Color _markerColor(Map<String, dynamic> row) {
  switch (_status(row)) {
    case 'AVAILABLE':
      return const Color(0xFF2E7D32);

    case 'LOW_STOCK':
      return const Color(0xFFEF6C00);

    case 'OUT_OF_STOCK':
      return const Color(0xFFC62828);

    case 'NO_DATA':
    default:
      return const Color(0xFF757575);
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendItem(color: Color(0xFF2E7D32), label: 'Available'),

        _LegendItem(color: Color(0xFFC62828), label: 'Out of Stock'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _StationTablePlaceholder extends StatefulWidget {
  const _StationTablePlaceholder({
    required this.rows,
    required this.selectedFilter,
  });

  final List<Map<String, dynamic>> rows;
  final OverviewFilter selectedFilter;

  @override
  State<_StationTablePlaceholder> createState() =>
      _StationTablePlaceholderState();
}

class _StationTablePlaceholderState extends State<_StationTablePlaceholder> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();

    final filteredRows = widget.rows.where((row) {
      if (query.isEmpty) {
        return true;
      }

      final station =
          row['filling_station_name']?.toString().toLowerCase() ?? '';
      final district = row['district_name']?.toString().toLowerCase() ?? '';
      final omc = row['omc']?.toString().toLowerCase() ?? '';

      return station.contains(query) ||
          district.contains(query) ||
          omc.contains(query);
    }).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Stations – Fuel Stocks',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${filteredRows.length} records',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search station, district or OMC...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF4F7F6),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const Divider(height: 1),

SizedBox(
  height: 380,
  child: filteredRows.isEmpty
      ? const Center(
                    child: Text(
                      'No station stock records available.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.4),
                        1: FlexColumnWidth(1.3),
                        2: FlexColumnWidth(1.4),
                        3: FlexColumnWidth(1.0),
                        4: FlexColumnWidth(1.3),
                        5: FlexColumnWidth(1.4),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(color: Colors.black12),
                      ),
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFFF4F7F6)),
                          children: [
                            _TableHeaderCell('Station'),
                            _TableHeaderCell('District'),
                            _TableHeaderCell('OMC'),
                            _TableHeaderCell('Product'),
                            _TableHeaderCell('Stock'),
                            _TableHeaderCell('Status'),
                          ],
                        ),
                        ...filteredRows.map(
                          (row) => TableRow(
                            children: [
                              _TableTextCell(
                                row['filling_station_name']?.toString() ?? '—',
                              ),
                              _TableTextCell(
                                row['district_name']?.toString() ?? '—',
                              ),
                              _TableTextCell(row['omc']?.toString() ?? '—'),
                              _TableTextCell(row['product']?.toString() ?? '—'),
                              _TableTextCell(
                                _tableStockValue(row),
                                alignRight: true,
                              ),
                              _TableStatusCell(status: _status(row)),
                            ],
                          ),
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

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _TableTextCell extends StatelessWidget {
  const _TableTextCell(this.text, {this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _TableStatusCell extends StatelessWidget {
  const _TableStatusCell({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'AVAILABLE' => const Color(0xFF2E7D32),
      'LOW_STOCK' => const Color(0xFFEF6C00),
      'OUT_OF_STOCK' => const Color(0xFFC62828),
      _ => const Color(0xFF757575),
    };

    final label = switch (status) {
      'LOW_STOCK' => 'Low Stock',
      'OUT_OF_STOCK' => 'Out',
      'NO_DATA' => 'No Data',
      _ => 'Available',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _tableStockValue(Map<String, dynamic> row) {
  if (_status(row) == 'NO_DATA') {
    return '—';
  }

  final value = (row['current_stock_litres'] as num?)?.toDouble();

  if (value == null) {
    return '—';
  }

  return '${_formatLitres(value)} L';
}

class _OverviewCardData {
  const _OverviewCardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.backgroundColor,
    required this.accentColor,
    required this.filter,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color backgroundColor;
  final Color accentColor;
  final OverviewFilter filter;
}

List<Map<String, dynamic>> _rowsForProduct(
  List<Map<String, dynamic>> rows,
  String product,
) {
  return rows.where((row) {
    return row['product']?.toString().toUpperCase() == product;
  }).toList();
}

double _totalStock(List<Map<String, dynamic>> rows) {
  return rows
      .where((row) => _status(row) != 'NO_DATA')
      .fold<double>(
        0,
        (total, row) =>
            total + ((row['current_stock_litres'] as num?)?.toDouble() ?? 0),
      );
}

int _reportingStations(List<Map<String, dynamic>> rows) {
  return rows.where((row) {
    return _status(row) != 'NO_DATA';
  }).length;
}

String _status(Map<String, dynamic> row) {
  return row['stock_status']?.toString().toUpperCase() ?? 'NO_DATA';
}

List<Map<String, dynamic>> _applyFilter(
  List<Map<String, dynamic>> rows,
  OverviewFilter filter,
) {
  switch (filter) {
    case OverviewFilter.petrol:
      return _rowsForProduct(rows, 'PETROL');

    case OverviewFilter.diesel:
      return _rowsForProduct(rows, 'DIESEL');

    case OverviewFilter.lowStock:
      return rows.where((row) {
        return _status(row) == 'LOW_STOCK';
      }).toList();

    case OverviewFilter.all:
      return rows;
  }
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
