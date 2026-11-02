import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/dashboard_service.dart';

class StationsPage extends StatefulWidget {
  const StationsPage({super.key});

  @override
  State<StationsPage> createState() => _StationsPageState();
}

class _StationsPageState extends State<StationsPage> {
  final DashboardService _service = DashboardService();

  late Future<_StationPageData> _future;

  String _region = 'All';
  String _omc = 'All';
  String _district = 'All';
  String _status = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _loadData();
  }

  Future<_StationPageData> _loadData() async {
    final results = await Future.wait([
      _service.getStationIntelligence(),
      _service.getStationConsumption(),
      _service.getStationRejections(),
      _service.getRegionalFuelReceipts(),
    ]);

    return _StationPageData(
      stations: results[0],
      consumption: results[1],
      rejections: results[2],
      regionalReceipts: results[3],
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  void _clearFilters() {
    setState(() {
      _region = 'All';
      _omc = 'All';
      _district = 'All';
      _status = 'All';
      _search = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StationPageData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load station intelligence: '
                '${snapshot.error}',
              ),
            ),
          );
        }

        final data = snapshot.data!;

        final consumption = _consumptionLookup(data.consumption);
        final rejections = _rejectionLookup(data.rejections);

        final regions = _unique(data.stations, 'region');
        final omcs = _unique(data.stations, 'omc');
        final districts = _unique(data.stations, 'district_name');
        final statuses = _uniqueStatus(data.stations);

        final rows = data.stations.where((row) {
          if (_region != 'All' && _text(row['region']) != _region) {
            return false;
          }

          if (_omc != 'All' && _text(row['omc']) != _omc) {
            return false;
          }

          if (_district != 'All' && _text(row['district_name']) != _district) {
            return false;
          }

          final rowStatus = _stationStatus(row);

          if (_status != 'All' && rowStatus != _status) {
            return false;
          }

          final query = _search.trim().toLowerCase();

          if (query.isNotEmpty) {
            final station = _text(row['filling_station_name']).toLowerCase();
            final district = _text(row['district_name']).toLowerCase();
            final omc = _text(row['omc']).toLowerCase();
            final licence = _text(row['licence_number']).toLowerCase();

            if (!station.contains(query) &&
                !district.contains(query) &&
                !omc.contains(query) &&
                !licence.contains(query)) {
              return false;
            }
          }

          return true;
        }).toList();

        final visibleIds = rows
            .map((row) => _text(row['filling_station_id']))
            .toSet();

        final visibleConsumption = data.consumption.where((row) {
          return visibleIds.contains(_text(row['filling_station_id']));
        }).toList();

        final visibleRejections = data.rejections.where((row) {
          return visibleIds.contains(_text(row['filling_station_id']));
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
                    _Header(onRefresh: _refresh),
                    const SizedBox(height: 22),

                    _StatusCards(rows: rows),

                    const SizedBox(height: 20),

                    _Filters(
                      regions: regions,
                      omcs: omcs,
                      districts: districts,
                      statuses: statuses,
                      selectedRegion: _region,
                      selectedOmc: _omc,
                      selectedDistrict: _district,
                      selectedStatus: _status,
                      search: _search,
                      onRegion: (value) {
                        setState(() => _region = value ?? 'All');
                      },
                      onOmc: (value) {
                        setState(() => _omc = value ?? 'All');
                      },
                      onDistrict: (value) {
                        setState(() => _district = value ?? 'All');
                      },
                      onStatus: (value) {
                        setState(() => _status = value ?? 'All');
                      },
                      onSearch: (value) {
                        setState(() => _search = value);
                      },
                      onClear: _clearFilters,
                    ),

                    const SizedBox(height: 20),

                    _RegionalReceipts(rows: data.regionalReceipts),

                    const SizedBox(height: 20),

                    _OperationalIntelligence(
                      stations: rows,
                      consumption: visibleConsumption,
                      rejections: visibleRejections,
                    ),

                    const SizedBox(height: 20),

                    _MapAndTable(
                      rows: rows,
                      consumption: consumption,
                      rejections: rejections,
                    ),
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
  const _Header({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fuelling Station Statistics',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'National filling station monitoring and fuel intelligence',
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _StatusCards extends StatelessWidget {
  const _StatusCards({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    int count(String status) {
      return rows.where((row) => _stationStatus(row) == status).length;
    }

    final cards = [
      _CardData(
        title: 'Total Stations',
        value: '${rows.length}',
        icon: Icons.local_gas_station,
        background: const Color(0xFFD9EAD3),
        accent: const Color(0xFF38761D),
      ),
      _CardData(
        title: 'Operational',
        value: '${count('Operational')}',
        icon: Icons.check_circle_outline,
        background: const Color(0xFFDDF2E5),
        accent: const Color(0xFF287A46),
      ),
      _CardData(
        title: 'Under Construction',
        value: '${count('Under construction')}',
        icon: Icons.construction_outlined,
        background: const Color(0xFFFFEDC2),
        accent: const Color(0xFF8A6500),
      ),
      _CardData(
        title: 'Approved to Construct',
        value: '${count('Approved to Construct')}',
        icon: Icons.approval_outlined,
        background: const Color(0xFFDDEAF7),
        accent: const Color(0xFF356C9B),
      ),
      _CardData(
        title: 'Not Operational',
        value: '${count('Not Operational')}',
        icon: Icons.block_outlined,
        background: const Color(0xFFF6DADA),
        accent: const Color(0xFFA83A3A),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final cardWidth = width >= 1250
            ? (width - 64) / 5
            : width >= 750
            ? (width - 32) / 3
            : width >= 500
            ? (width - 16) / 2
            : width;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              height: 125,
              child: _StatusCard(data: card),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.data});

  final _CardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: data.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
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

class _Filters extends StatelessWidget {
  const _Filters({
    required this.regions,
    required this.omcs,
    required this.districts,
    required this.statuses,
    required this.selectedRegion,
    required this.selectedOmc,
    required this.selectedDistrict,
    required this.selectedStatus,
    required this.search,
    required this.onRegion,
    required this.onOmc,
    required this.onDistrict,
    required this.onStatus,
    required this.onSearch,
    required this.onClear,
  });

  final List<String> regions;
  final List<String> omcs;
  final List<String> districts;
  final List<String> statuses;

  final String selectedRegion;
  final String selectedOmc;
  final String selectedDistrict;
  final String selectedStatus;
  final String search;

  final ValueChanged<String?> onRegion;
  final ValueChanged<String?> onOmc;
  final ValueChanged<String?> onDistrict;
  final ValueChanged<String?> onStatus;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Filter Stations',
      subtitle:
          'Filter all station intelligence by geography, OMC or operational status',
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
                    child: _Dropdown(
                      label: 'Region',
                      value: selectedRegion,
                      values: ['All', ...regions],
                      onChanged: onRegion,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'OMC',
                      value: selectedOmc,
                      values: ['All', ...omcs],
                      onChanged: onOmc,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'District',
                      value: selectedDistrict,
                      values: ['All', ...districts],
                      onChanged: onDistrict,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'Operational Status',
                      value: selectedStatus,
                      values: ['All', ...statuses],
                      onChanged: onStatus,
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
                  controller: TextEditingController(
                    text: search,
                  )..selection = TextSelection.collapsed(offset: search.length),
                  onChanged: onSearch,
                  decoration: InputDecoration(
                    hintText:
                        'Search station, OMC, district or licence number...',
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

class _Dropdown extends StatelessWidget {
  const _Dropdown({
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
      items: values.map((value) {
        return DropdownMenuItem(value: value, child: Text(value));
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _RegionalReceipts extends StatelessWidget {
  const _RegionalReceipts({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};

    for (final row in rows) {
      final region = _text(row['region']);

      if (region.isEmpty) {
        continue;
      }

      totals[region] =
          (totals[region] ?? 0) + _number(row['total_received_litres']);
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maximum = sorted.isEmpty ? 1.0 : sorted.first.value;

    return _Panel(
      title: 'Regional Fuel Receipts',
      subtitle: 'Cumulative recorded Petrol and Diesel receipts by region',
      child: sorted.isEmpty
          ? const SizedBox(
              height: 130,
              child: Center(child: Text('No receipt data available')),
            )
          : Column(
              children: sorted.map((entry) {
                final petrol = rows
                    .where(
                      (row) =>
                          _text(row['region']) == entry.key &&
                          _text(row['product']).toUpperCase() == 'PETROL',
                    )
                    .fold<double>(
                      0,
                      (sum, row) => sum + _number(row['total_received_litres']),
                    );

                final diesel = rows
                    .where(
                      (row) =>
                          _text(row['region']) == entry.key &&
                          _text(row['product']).toUpperCase() == 'DIESEL',
                    )
                    .fold<double>(
                      0,
                      (sum, row) => sum + _number(row['total_received_litres']),
                    );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${entry.key} Region',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${_litres(entry.value)} L',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: maximum <= 0 ? 0 : entry.value / maximum,
                        minHeight: 9,
                        borderRadius: BorderRadius.circular(10),
                        backgroundColor: const Color(0xFFE8EEEC),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Petrol ${_litres(petrol)} L  •  '
                        'Diesel ${_litres(diesel)} L',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _OperationalIntelligence extends StatelessWidget {
  const _OperationalIntelligence({
    required this.stations,
    required this.consumption,
    required this.rejections,
  });

  final List<Map<String, dynamic>> stations;
  final List<Map<String, dynamic>> consumption;
  final List<Map<String, dynamic>> rejections;

  @override
  Widget build(BuildContext context) {
    final sufficient =
        consumption
            .where(
              (row) =>
                  _text(row['consumption_data_status']) == 'SUFFICIENT' &&
                  row['estimated_daily_consumption_litres'] != null,
            )
            .toList()
          ..sort(
            (a, b) => _number(
              b['estimated_daily_consumption_litres'],
            ).compareTo(_number(a['estimated_daily_consumption_litres'])),
          );

    final stationLookup = {
      for (final station in stations)
        _text(station['filling_station_id']): station,
    };

    final rejectionRows =
        rejections.where((row) => _int(row['rejection_count']) > 0).toList()
          ..sort(
            (a, b) => _int(
              b['rejection_count'],
            ).compareTo(_int(a['rejection_count'])),
          );

    final highConsumption = sufficient.take(5).toList();
    final highRejections = rejectionRows.take(5).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final first = _Panel(
          title: 'Highest Estimated Consumption',
          subtitle: 'Stations with sufficient stock observation history',
          child: SizedBox(
            height: 220,
            child: highConsumption.isEmpty
                ? const Center(
                    child: Text(
                      'Insufficient consumption history',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    itemCount: highConsumption.length,
                    separatorBuilder: (_, _) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final row = highConsumption[index];
                      final station =
                          stationLookup[_text(row['filling_station_id'])];

                      return Row(
                        children: [
                          CircleAvatar(radius: 15, child: Text('${index + 1}')),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station == null
                                      ? 'Unknown station'
                                      : _text(station['filling_station_name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _text(row['product']),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${_litres(_number(row['estimated_daily_consumption_litres']))} L/day',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        );

        final second = _Panel(
          title: 'Fuel Rejection Cases',
          subtitle: 'Stations with recorded motorcycle fueling rejections',
          child: SizedBox(
            height: 220,
            child: highRejections.isEmpty
                ? const Center(
                    child: Text(
                      'No rejection cases recorded',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    itemCount: highRejections.length,
                    separatorBuilder: (_, _) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final row = highRejections[index];
                      final station =
                          stationLookup[_text(row['filling_station_id'])];

                      return Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFC62828),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  station == null
                                      ? 'Unknown station'
                                      : _text(station['filling_station_name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Already fueled: '
                                  '${_int(row['already_fueled_count'])}  •  '
                                  'Conflict: '
                                  '${_int(row['identifier_conflict_count'])}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${_int(row['rejection_count'])}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFC62828),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        );

        if (constraints.maxWidth < 950) {
          return Column(children: [first, const SizedBox(height: 16), second]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _MapAndTable extends StatelessWidget {
  const _MapAndTable({
    required this.rows,
    required this.consumption,
    required this.rejections,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, Map<String, Map<String, dynamic>>> consumption;
  final Map<String, Map<String, dynamic>> rejections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return Column(
            children: [
              _StationMap(rows: rows),
              const SizedBox(height: 20),
              _StationTable(
                rows: rows,
                consumption: consumption,
                rejections: rejections,
              ),
            ],
          );
        }

        return SizedBox(
          height: 660,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: _StationMap(rows: rows)),
              const SizedBox(width: 20),
              Expanded(
                flex: 8,
                child: _StationTable(
                  rows: rows,
                  consumption: consumption,
                  rejections: rejections,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StationMap extends StatelessWidget {
  const _StationMap({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final mappable = rows
        .where((row) => row['latitude'] is num && row['longitude'] is num)
        .toList();

    final markers = mappable.map((row) {
      final status = _stationStatus(row);

      final color = switch (status) {
        'Operational' => const Color(0xFF2E7D32),
        'Under construction' => const Color(0xFFEF6C00),
        'Approved to Construct' => const Color(0xFF1565C0),
        'Not Operational' => const Color(0xFFC62828),
        _ => const Color(0xFF757575),
      };

      return Marker(
        point: LatLng(
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble(),
        ),
        width: 34,
        height: 34,
        child: Tooltip(
          message:
              '${_text(row['filling_station_name'])}\n'
              '${_text(row['district_name'])} • '
              '${_text(row['omc'])}\n'
              '$status\n'
              'Petrol: ${_stockText(row['current_petrol_litres'])}\n'
              'Diesel: ${_stockText(row['current_diesel_litres'])}',
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
              Icons.local_gas_station,
              color: Colors.white,
              size: 17,
            ),
          ),
        ),
      );
    }).toList();

    return _Panel(
      title: 'National Station Map',
      subtitle: '${mappable.length} of ${rows.length} filtered stations mapped',
      child: SizedBox(
        height: 545,
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

class _StationTable extends StatelessWidget {
  const _StationTable({
    required this.rows,
    required this.consumption,
    required this.rejections,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, Map<String, Map<String, dynamic>>> consumption;
  final Map<String, Map<String, dynamic>> rejections;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Station Intelligence',
      subtitle:
          'Current stock, receipts, estimated consumption and rejection monitoring',
      child: SizedBox(
        height: 545,
        child: rows.isEmpty
            ? const Center(
                child: Text('No stations match the selected filters.'),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1500,
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.4),
                        1: FlexColumnWidth(1.1),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(1.2),
                        4: FlexColumnWidth(1.2),
                        5: FlexColumnWidth(1.5),
                        6: FlexColumnWidth(1.5),
                        7: FlexColumnWidth(1.5),
                        8: FlexColumnWidth(1.5),
                        9: FlexColumnWidth(1.4),
                        10: FlexColumnWidth(1.0),
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
                            _TH('Status'),
                            _TH('Petrol Stock'),
                            _TH('Last Petrol Receipt'),
                            _TH('Petrol L/day'),
                            _TH('Diesel Stock'),
                            _TH('Last Diesel Receipt'),
                            _TH('Diesel L/day'),
                            _TH('Rejects'),
                          ],
                        ),
                        ...rows.map((row) {
                          final id = _text(row['filling_station_id']);

                          final petrol = consumption[id]?['PETROL'];

                          final diesel = consumption[id]?['DIESEL'];

                          final rejection = rejections[id];

                          return TableRow(
                            children: [
                              _TD(_text(row['filling_station_name'])),
                              _TD(_text(row['district_name'])),
                              _TD(_text(row['omc'])),
                              _TD(_stationStatus(row)),
                              _TD(
                                _stockText(row['current_petrol_litres']),
                                right: true,
                              ),
                              _TD(
                                _receiptText(
                                  row['last_petrol_received_at'],
                                  row['last_petrol_received_litres'],
                                ),
                              ),
                              _TD(_consumptionText(petrol), right: true),
                              _TD(
                                _stockText(row['current_diesel_litres']),
                                right: true,
                              ),
                              _TD(
                                _receiptText(
                                  row['last_diesel_received_at'],
                                  row['last_diesel_received_litres'],
                                ),
                              ),
                              _TD(_consumptionText(diesel), right: true),
                              _TD(
                                '${_int(rejection?['rejection_count'])}',
                                right: true,
                              ),
                            ],
                          );
                        }),
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
        text.isEmpty ? '—' : text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _CardData {
  const _CardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.background,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color background;
  final Color accent;
}

class _StationPageData {
  const _StationPageData({
    required this.stations,
    required this.consumption,
    required this.rejections,
    required this.regionalReceipts,
  });

  final List<Map<String, dynamic>> stations;
  final List<Map<String, dynamic>> consumption;
  final List<Map<String, dynamic>> rejections;
  final List<Map<String, dynamic>> regionalReceipts;
}

Map<String, Map<String, Map<String, dynamic>>> _consumptionLookup(
  List<Map<String, dynamic>> rows,
) {
  final result = <String, Map<String, Map<String, dynamic>>>{};

  for (final row in rows) {
    final station = _text(row['filling_station_id']);
    final product = _text(row['product']).toUpperCase();

    if (station.isEmpty || product.isEmpty) {
      continue;
    }

    result.putIfAbsent(station, () => <String, Map<String, dynamic>>{});

    result[station]![product] = row;
  }

  return result;
}

Map<String, Map<String, dynamic>> _rejectionLookup(
  List<Map<String, dynamic>> rows,
) {
  return {for (final row in rows) _text(row['filling_station_id']): row};
}

List<String> _unique(List<Map<String, dynamic>> rows, String field) {
  final values = rows
      .map((row) => _text(row[field]))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  values.sort();

  return values;
}

List<String> _uniqueStatus(List<Map<String, dynamic>> rows) {
  final values = rows.map(_stationStatus).toSet().toList();

  values.sort();

  return values;
}

String _stationStatus(Map<String, dynamic> row) {
  final value = _text(row['operational_status']);

  return value.isEmpty ? 'No Status' : value;
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}

double _number(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _int(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _litres(double value) {
  final number = value.round().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < number.length; i++) {
    final remaining = number.length - i;

    buffer.write(number[i]);

    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return buffer.toString();
}

String _stockText(dynamic value) {
  if (value == null) {
    return 'No data';
  }

  return '${_litres(_number(value))} L';
}

String _consumptionText(Map<String, dynamic>? row) {
  if (row == null) {
    return 'Insufficient';
  }

  if (_text(row['consumption_data_status']) != 'SUFFICIENT') {
    return 'Insufficient';
  }

  final value = row['estimated_daily_consumption_litres'];

  if (value == null) {
    return 'Insufficient';
  }

  return '${_litres(_number(value))} L/day';
}

String _receiptText(dynamic dateValue, dynamic litresValue) {
  if (dateValue == null) {
    return 'No receipt recorded';
  }

  final date = DateTime.tryParse(dateValue.toString());

  if (date == null) {
    return 'No receipt recorded';
  }

  final malawi = date.toUtc().add(const Duration(hours: 2));

  final day = malawi.day.toString().padLeft(2, '0');
  final month = malawi.month.toString().padLeft(2, '0');

  final quantity = litresValue == null
      ? ''
      : '${_litres(_number(litresValue))} L • ';

  return '$quantity$day/$month/${malawi.year}';
}
