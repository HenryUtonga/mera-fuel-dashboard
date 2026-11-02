import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';

class FuelingActivityPage extends StatefulWidget {
  const FuelingActivityPage({super.key});

  @override
  State<FuelingActivityPage> createState() => _FuelingActivityPageState();
}

class _FuelingActivityPageState extends State<FuelingActivityPage> {
  final DashboardService _dashboardService = DashboardService();

  late Future<List<Map<String, dynamic>>> _activityFuture;

  DateTime _selectedDate = DateTime.now();

  String _selectedRegion = 'All';
  String _selectedOmc = 'All';
  String _selectedStation = 'All';
  String _selectedFuelType = 'All';
  String _selectedRestriction = 'All';
  String _selectedConflict = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  void _loadActivity() {
    _activityFuture = _dashboardService.getFuelingActivity(date: _selectedDate);
  }

  Future<void> _refresh() async {
    setState(_loadActivity);
    await _activityFuture;
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );

      _resetFilters();
      _loadActivity();
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _resetFilters();
      _loadActivity();
    });
  }

  void _resetFilters() {
    _selectedRegion = 'All';
    _selectedOmc = 'All';
    _selectedStation = 'All';
    _selectedFuelType = 'All';
    _selectedRestriction = 'All';
    _selectedConflict = 'All';
    _searchQuery = '';
  }

  void _clearFilters() {
    setState(_resetFilters);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _activityFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Unable to load fueling activity: ${snapshot.error}'),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        final regions = _unique(rows, 'region');
        final omcs = _unique(rows, 'omc');
        final stations = _unique(rows, 'filling_station_name');
        final fuelTypes = _unique(rows, 'fuel_type');
        final restrictions = _unique(rows, 'restriction_type_at_fueling');

        final filteredRows = rows.where((row) {
          if (_selectedRegion != 'All' &&
              _text(row['region']) != _selectedRegion) {
            return false;
          }

          if (_selectedOmc != 'All' && _text(row['omc']) != _selectedOmc) {
            return false;
          }

          if (_selectedStation != 'All' &&
              _text(row['filling_station_name']) != _selectedStation) {
            return false;
          }

          if (_selectedFuelType != 'All' &&
              _text(row['fuel_type']) != _selectedFuelType) {
            return false;
          }

          if (_selectedRestriction != 'All') {
            final restriction = _text(row['restriction_type_at_fueling']);

            if (_selectedRestriction == 'No restriction data') {
              if (restriction.isNotEmpty) {
                return false;
              }
            } else if (restriction != _selectedRestriction) {
              return false;
            }
          }

          if (_selectedConflict == 'Conflicts only' &&
              !_bool(row['sync_conflict'])) {
            return false;
          }

          if (_selectedConflict == 'No conflicts' &&
              _bool(row['sync_conflict'])) {
            return false;
          }

          final query = _searchQuery.trim().toLowerCase();

          if (query.isNotEmpty) {
            final searchable = [
              row['vehicle_code'],
              row['plate_number'],
              row['driver_id_number'],
              row['filling_station_name'],
              row['district_name'],
              row['omc'],
              row['attendant_name'],
              row['attendant_id'],
              row['device_id'],
              row['identification_method'],
            ].map(_text).join(' ').toLowerCase();

            if (!searchable.contains(query)) {
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
                      stations: stations,
                      fuelTypes: fuelTypes,
                      restrictions: restrictions,
                      selectedRegion: _selectedRegion,
                      selectedOmc: _selectedOmc,
                      selectedStation: _selectedStation,
                      selectedFuelType: _selectedFuelType,
                      selectedRestriction: _selectedRestriction,
                      selectedConflict: _selectedConflict,
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
                      onStationChanged: (value) {
                        setState(() {
                          _selectedStation = value ?? 'All';
                        });
                      },
                      onFuelTypeChanged: (value) {
                        setState(() {
                          _selectedFuelType = value ?? 'All';
                        });
                      },
                      onRestrictionChanged: (value) {
                        setState(() {
                          _selectedRestriction = value ?? 'All';
                        });
                      },
                      onConflictChanged: (value) {
                        setState(() {
                          _selectedConflict = value ?? 'All';
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
                    _ActivityBreakdown(rows: filteredRows),
                    const SizedBox(height: 20),
                    _AuditTable(rows: filteredRows),
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
              'Fueling Activity',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Fueling transaction and audit activity for '
              '${_formatDate(selectedDate)}',
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

        if (constraints.maxWidth < 850) {
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
    final stations = rows
        .map((row) => _text(row['filling_station_id']))
        .where((value) => value.isNotEmpty)
        .toSet();

    final vehicles = rows
        .map((row) {
          final id = _text(row['vehicle_id']);

          if (id.isNotEmpty) {
            return id;
          }

          final code = _text(row['vehicle_code']);

          if (code.isNotEmpty) {
            return code;
          }

          return _text(row['plate_number']);
        })
        .where((value) => value.isNotEmpty)
        .toSet();

    final conflicts = rows.where((row) => _bool(row['sync_conflict'])).length;

    final overrides = rows.where((row) => _bool(row['override_used'])).length;

    final cards = [
      _CardData(
        title: 'Fuelings',
        value: '${rows.length}',
        icon: Icons.ev_station,
        background: const Color(0xFFD9EAD3),
        accent: const Color(0xFF38761D),
      ),
      _CardData(
        title: 'Unique Vehicles',
        value: '${vehicles.length}',
        icon: Icons.two_wheeler_outlined,
        background: const Color(0xFFDDEAF7),
        accent: const Color(0xFF356C9B),
      ),
      _CardData(
        title: 'Active Stations',
        value: '${stations.length}',
        icon: Icons.local_gas_station_outlined,
        background: const Color(0xFFE7E2F4),
        accent: const Color(0xFF65538D),
      ),
      _CardData(
        title: 'Sync Conflicts',
        value: '$conflicts',
        icon: Icons.sync_problem_outlined,
        background: const Color(0xFFF6DADA),
        accent: const Color(0xFFA83A3A),
      ),
      _CardData(
        title: 'Overrides',
        value: '$overrides',
        icon: Icons.admin_panel_settings_outlined,
        background: const Color(0xFFFFEDC2),
        accent: const Color(0xFF8A6500),
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
              child: _SummaryCard(data: card),
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

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.regions,
    required this.omcs,
    required this.stations,
    required this.fuelTypes,
    required this.restrictions,
    required this.selectedRegion,
    required this.selectedOmc,
    required this.selectedStation,
    required this.selectedFuelType,
    required this.selectedRestriction,
    required this.selectedConflict,
    required this.searchQuery,
    required this.onRegionChanged,
    required this.onOmcChanged,
    required this.onStationChanged,
    required this.onFuelTypeChanged,
    required this.onRestrictionChanged,
    required this.onConflictChanged,
    required this.onSearchChanged,
    required this.onClear,
  });

  final List<String> regions;
  final List<String> omcs;
  final List<String> stations;
  final List<String> fuelTypes;
  final List<String> restrictions;

  final String selectedRegion;
  final String selectedOmc;
  final String selectedStation;
  final String selectedFuelType;
  final String selectedRestriction;
  final String selectedConflict;
  final String searchQuery;

  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<String?> onOmcChanged;
  final ValueChanged<String?> onStationChanged;
  final ValueChanged<String?> onFuelTypeChanged;
  final ValueChanged<String?> onRestrictionChanged;
  final ValueChanged<String?> onConflictChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final restrictionValues = ['All', ...restrictions, 'No restriction data'];

    return _Panel(
      title: 'Filter Fueling Activity',
      subtitle: 'Search and filter the daily fueling transaction audit trail',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              final fieldWidth = width >= 1200
                  ? (width - 48) / 4
                  : width >= 700
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
                      onChanged: onRegionChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'OMC',
                      value: selectedOmc,
                      values: ['All', ...omcs],
                      onChanged: onOmcChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'Station',
                      value: selectedStation,
                      values: ['All', ...stations],
                      onChanged: onStationChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'Fuel Type',
                      value: selectedFuelType,
                      values: ['All', ...fuelTypes],
                      onChanged: onFuelTypeChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'Restriction',
                      value: selectedRestriction,
                      values: restrictionValues,
                      onChanged: onRestrictionChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _Dropdown(
                      label: 'Sync Conflict',
                      value: selectedConflict,
                      values: const ['All', 'Conflicts only', 'No conflicts'],
                      onChanged: onConflictChanged,
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
                child: TextFormField(
                  initialValue: searchQuery,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText:
                        'Search vehicle, plate, station, attendant, device or identification method...',
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
    final cleanValues = values.toSet().toList();

    return DropdownButtonFormField<String>(
      initialValue: cleanValues.contains(value) ? value : 'All',
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
      items: cleanValues.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

class _ActivityBreakdown extends StatelessWidget {
  const _ActivityBreakdown({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final stationCounts = <String, int>{};
    final attendantCounts = <String, int>{};

    for (final row in rows) {
      final station = _text(row['filling_station_name']);

      if (station.isNotEmpty) {
        stationCounts[station] = (stationCounts[station] ?? 0) + 1;
      }

      final attendantName = _attendantName(row);

      if (attendantName.isNotEmpty) {
        attendantCounts[attendantName] =
            (attendantCounts[attendantName] ?? 0) + 1;
      }
    }

    final stationEntries = stationCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final attendantEntries = attendantCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topStations = stationEntries.take(8).toList();
    final topAttendants = attendantEntries.take(8).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stationPanel = _RankingPanel(
          title: 'Fuelings by Station',
          subtitle: 'Stations processing the most fueling transactions',
          rows: topStations,
          icon: Icons.local_gas_station_outlined,
        );

        final attendantPanel = _RankingPanel(
          title: 'Fuelings by Attendant',
          subtitle: 'Attendants processing the most fueling transactions',
          rows: topAttendants,
          icon: Icons.badge_outlined,
        );

        if (constraints.maxWidth < 950) {
          return Column(
            children: [
              stationPanel,
              const SizedBox(height: 16),
              attendantPanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: stationPanel),
            const SizedBox(width: 16),
            Expanded(child: attendantPanel),
          ],
        );
      },
    );
  }
}

class _RankingPanel extends StatelessWidget {
  const _RankingPanel({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<MapEntry<String, int>> rows;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final maximum = rows.isEmpty ? 1 : rows.first.value;

    return _Panel(
      title: title,
      subtitle: subtitle,
      child: SizedBox(
        height: 245,
        child: rows.isEmpty
            ? const Center(
                child: Text(
                  'No activity recorded',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = rows[index];

                  return Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F2EF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: const Color(0xFF006B54),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
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
                                const SizedBox(width: 10),
                                Text(
                                  '${entry.value}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            LinearProgressIndicator(
                              value: maximum == 0 ? 0 : entry.value / maximum,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(10),
                              backgroundColor: const Color(0xFFE8EEEC),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _AuditTable extends StatelessWidget {
  const _AuditTable({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Fueling Transaction Audit',
      subtitle: '${rows.length} transactions matching the selected filters',
      child: SizedBox(
        height: 620,
        child: rows.isEmpty
            ? const Center(
                child: Text(
                  'No fueling activity found for this selection.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1800,
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(0.9),
                        1: FlexColumnWidth(2.0),
                        2: FlexColumnWidth(1.4),
                        3: FlexColumnWidth(1.2),
                        4: FlexColumnWidth(1.1),
                        5: FlexColumnWidth(1.5),
                        6: FlexColumnWidth(1.4),
                        7: FlexColumnWidth(1.5),
                        8: FlexColumnWidth(1.1),
                        9: FlexColumnWidth(1.1),
                        10: FlexColumnWidth(1.1),
                        11: FlexColumnWidth(1.4),
                      },
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: Colors.black12),
                      ),
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFFF4F7F6)),
                          children: [
                            _TH('Time'),
                            _TH('Station'),
                            _TH('Vehicle / Motorcycle'),
                            _TH('Plate'),
                            _TH('Fuel'),
                            _TH('Attendant'),
                            _TH('Identification'),
                            _TH('Restriction'),
                            _TH('Device'),
                            _TH('Override'),
                            _TH('Conflict'),
                            _TH('District / OMC'),
                          ],
                        ),
                        ...rows.map((row) {
                          return TableRow(
                            decoration: _bool(row['sync_conflict'])
                                ? const BoxDecoration(color: Color(0xFFFFF1F1))
                                : null,
                            children: [
                              _TD(_formatTime(row['fueled_at'])),
                              _TD(_text(row['filling_station_name'])),
                              _TD(_vehicleIdentifier(row)),
                              _TD(_text(row['plate_number'])),
                              _TD(_text(row['fuel_type'])),
                              _TD(_attendantName(row)),
                              _TD(_displayValue(row['identification_method'])),
                              _TD(_restrictionText(row)),
                              _TD(_text(row['device_id'])),
                              _TD(_bool(row['override_used']) ? 'YES' : 'No'),
                              _TD(
                                _bool(row['sync_conflict'])
                                    ? _conflictText(row)
                                    : 'No',
                              ),
                              _TD(
                                '${_text(row['district_name'])}'
                                '${_text(row['omc']).isEmpty ? '' : ' - ${_text(row['omc'])}'}',
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
  const _TD(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Tooltip(
        message: text.isEmpty ? '—' : text,
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
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

List<String> _unique(List<Map<String, dynamic>> rows, String field) {
  final values = rows
      .map((row) => _text(row[field]))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  values.sort();

  return values;
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}

bool _bool(dynamic value) {
  if (value is bool) {
    return value;
  }

  return value?.toString().toLowerCase() == 'true';
}

String _vehicleIdentifier(Map<String, dynamic> row) {
  final code = _text(row['vehicle_code']);

  if (code.isNotEmpty) {
    return code;
  }

  final plate = _text(row['plate_number']);

  if (plate.isNotEmpty) {
    return plate;
  }

  final id = _text(row['vehicle_id']);

  if (id.isNotEmpty) {
    return id;
  }

  return 'Unknown';
}

String _attendantName(Map<String, dynamic> row) {
  final name = _text(row['attendant_name']);

  if (name.isNotEmpty) {
    return name;
  }

  final attendant = _text(row['attendant_id']);

  if (attendant.isNotEmpty) {
    return attendant;
  }

  return 'Unknown';
}

String _restrictionText(Map<String, dynamic> row) {
  final type = _text(row['restriction_type_at_fueling']);

  if (type.isEmpty) {
    return 'No data';
  }

  final hours = row['restriction_hours_at_fueling'];

  if (hours == null) {
    return _displayValue(type);
  }

  return '${_displayValue(type)} (${hours}h)';
}

String _conflictText(Map<String, dynamic> row) {
  final reason = _text(row['conflict_reason']);

  if (reason.isNotEmpty) {
    return 'YES • $reason';
  }

  return 'YES';
}

String _displayValue(dynamic value) {
  final text = _text(value);

  if (text.isEmpty) {
    return 'No data';
  }

  return text
      .replaceAll('_', ' ')
      .split(' ')
      .map((part) {
        if (part.isEmpty) {
          return part;
        }

        return '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}';
      })
      .join(' ');
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
  final second = malawiTime.second.toString().padLeft(2, '0');

  return '$hour:$minute:$second';
}
