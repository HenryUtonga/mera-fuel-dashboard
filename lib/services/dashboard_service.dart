import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _paged(
    String view,
    String columns, {
    String? orderBy,
    bool ascending = true,
  }) async {
    const pageSize = 1000;
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final response = orderBy == null
          ? await _client.from(view).select(columns).range(offset, offset + pageSize - 1)
          : await _client.from(view).select(columns)
              .order(orderBy, ascending: ascending)
              .range(offset, offset + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(response);
      result.addAll(page);
      if (page.length < pageSize) return result;
      offset += pageSize;
    }
  }

  Future<List<Map<String, dynamic>>> getStationStockDashboard() => _paged(
    'admin_station_stock_dashboard',
    'filling_station_id, filling_station_name, district_id, product, '
    'current_stock_litres, low_stock_threshold_litres, stock_status, last_updated',
    orderBy: 'filling_station_name',
  );

  Future<int> getActiveStationCount() async =>
      (_client.rpc('dashboard_active_station_count').then((value) => (value as num).toInt()));

  DateTime _startUtc(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).subtract(const Duration(hours: 2));

  Future<List<Map<String, dynamic>>> getExpectedDeliveries({DateTime? date}) async {
    final start = _startUtc(date ?? DateTime.now());
    final end = start.add(const Duration(days: 1));
    final response = await _client.from('admin_expected_deliveries_dashboard').select(
      'delivery_id, filling_station_id, filling_station_name, district_id, '
      'district_name, region, omc, latitude, longitude, operational_status, '
      'active, product, quantity_litres, expected_delivery_at, recorded_at, '
      'omc_user_id, device_id, notes, created_at',
    ).gte('expected_delivery_at', start.toIso8601String())
     .lt('expected_delivery_at', end.toIso8601String())
     .order('expected_delivery_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getStationFuelStatus() async =>
      List<Map<String, dynamic>>.from(await _client.rpc('dashboard_station_fuel_status'));

  Future<List<Map<String, dynamic>>> getMotorcycleRejections() async =>
      List<Map<String, dynamic>>.from(await _client.rpc('dashboard_motorcycle_rejections'));

  Future<List<Map<String, dynamic>>> getStationIntelligence() => _paged(
    'admin_station_intelligence_dashboard',
    'filling_station_id, filling_station_name, district_id, district_name, '
    'region, omc, latitude, longitude, licence_number, operational_status, '
    'active, dealer_contact_details, location_description, '
    'current_petrol_litres, petrol_stock_status, petrol_stock_last_updated, '
    'current_diesel_litres, diesel_stock_status, diesel_stock_last_updated, '
    'last_petrol_received_at, last_petrol_received_litres, '
    'last_diesel_received_at, last_diesel_received_litres',
    orderBy: 'filling_station_name',
  );

  Future<List<Map<String, dynamic>>> getStationConsumption() => _paged(
    'admin_station_consumption_dashboard',
    'filling_station_id, product, valid_intervals, observed_consumption_litres, '
    'observed_days, estimated_daily_consumption_litres, '
    'consumption_data_status, observation_started_at, observation_ended_at',
  );

  Future<List<Map<String, dynamic>>> getStationRejections() => _paged(
    'admin_station_rejection_dashboard',
    'filling_station_id, total_attempts, rejection_count, already_fueled_count, '
    'identifier_conflict_count, invalid_count, last_rejection_at',
    orderBy: 'rejection_count', ascending: false,
  );

  Future<List<Map<String, dynamic>>> getRegionalFuelReceipts() => _paged(
    'admin_regional_fuel_receipts_dashboard',
    'region, product, receipt_count, stations_receiving, '
    'total_received_litres, latest_receipt_at',
    orderBy: 'total_received_litres', ascending: false,
  );

  Future<List<Map<String, dynamic>>> getFuelingActivity({DateTime? date}) async {
    final start = _startUtc(date ?? DateTime.now());
    final end = start.add(const Duration(days: 1));
    final response = await _client.from('admin_fueling_activity_dashboard').select(
      'fueling_id, fueled_at, vehicle_id, vehicle_code, plate_number, '
      'driver_id, driver_id_number, fuel_type, quantity_litres, attendant_id, '
      'attendant_staff_number, attendant_name, attendant_role, device_id, '
      'identification_method, override_used, override_reason, sync_conflict, '
      'conflict_with_fueling_id, conflict_reason, conflict_detected_at, '
      'restriction_type_at_fueling, restriction_hours_at_fueling, '
      'filling_station_id, filling_station_name, district_id, district_name, region, omc',
    ).gte('fueled_at', start.toIso8601String())
     .lt('fueled_at', end.toIso8601String()).order('fueled_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getFuelingAnalytics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = _startUtc(startDate);
    final end = _startUtc(endDate).add(const Duration(days: 1));
    const pageSize = 1000;
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final response = await _client.rpc('dashboard_fueling_analytics', params: {
        'p_start_at': start.toIso8601String(),
        'p_end_at': end.toIso8601String(),
      }).range(offset, offset + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(response);
      result.addAll(page);
      if (page.length < pageSize) return result;
      offset += pageSize;
    }
  }

  Future<List<Map<String, dynamic>>> getFuelConsumptionIntervals() => _paged(
    'admin_fuel_consumption_intervals',
    'filling_station_id, product, previous_count_at, current_count_at, '
    'previous_stock, current_stock, receipts_between_counts, consumption_litres',
    orderBy: 'current_count_at',
  );

  Future<List<Map<String, dynamic>>> getFuelDeliveryVariance() => _paged(
    'admin_fuel_delivery_variance',
    'filling_station_id, product, delivery_date, expected_count, receipt_count, '
    'expected_litres, actual_litres, variance_litres, comparison_status',
    orderBy: 'delivery_date', ascending: false,
  );

  Future<List<Map<String, dynamic>>> getStationReportingFreshness() async {
  try {
    const pageSize = 1000;
    var from = 0;

    final allRows = <Map<String, dynamic>>[];

    while (true) {
      final response = await _client
          .from('admin_station_reporting_freshness')
          .select(
            'filling_station_id, filling_station_name, omc, '
            'district_id, operational_status, active, '
            'last_report_at, total_stock_reports',
          )
          .order('filling_station_name')
          .range(from, from + pageSize - 1);

      final rows = List<Map<String, dynamic>>.from(response);

      allRows.addAll(rows);

      if (rows.length < pageSize) {
        break;
      }

      from += pageSize;
    }

    return allRows;
  } catch (error) {
    throw Exception(
      'Unable to load station reporting freshness: $error',
    );
  }
}

Future<List<Map<String, dynamic>>> getOmcReportingFreshness() async {
  try {
    final response = await _client
        .from('admin_omc_reporting_freshness')
        .select(
          'omc_id, omc_name, active, '
          'total_submissions, last_submission_at',
        )
        .order('omc_name');

    return List<Map<String, dynamic>>.from(response);
  } catch (error) {
    throw Exception('Unable to load OMC reporting freshness: $error');
  }
}
}
