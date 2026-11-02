import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getStationStockDashboard() async {
    try {
      final response = await _client
          .from('admin_station_stock_dashboard')
          .select(
            'filling_station_id, filling_station_name, district_id, '
            'product, current_stock_litres, low_stock_threshold_litres, '
            'stock_status, last_updated',
          )
          .order('filling_station_name')
          .order('product');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load the station stock dashboard: $error');
    }
  }

  Future<int> getActiveStationCount() async {
    try {
      final response = await _client.rpc('dashboard_active_station_count');

      return (response as num).toInt();
    } catch (error) {
      throw Exception('Unable to load active station count: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getExpectedDeliveries({
    DateTime? date,
  }) async {
    try {
      final selectedDate = date ?? DateTime.now();

      // MERA Fuel Control operates on Malawi calendar dates.
      // Malawi uses UTC+2 throughout the year.
      final startOfMalawiDayUtc = DateTime.utc(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      ).subtract(const Duration(hours: 2));

      final endOfMalawiDayUtc = startOfMalawiDayUtc.add(
        const Duration(days: 1),
      );

      final response = await _client
          .from('admin_expected_deliveries_dashboard')
          .select(
            'delivery_id, filling_station_id, filling_station_name, '
            'district_id, district_name, region, omc, latitude, longitude, '
            'operational_status, active, product, quantity_litres, '
            'expected_delivery_at, recorded_at, omc_user_id, '
            'device_id, notes, created_at',
          )
          .gte('expected_delivery_at', startOfMalawiDayUtc.toIso8601String())
          .lt('expected_delivery_at', endOfMalawiDayUtc.toIso8601String())
          .order('expected_delivery_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load expected deliveries: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getStationFuelStatus() async {
    try {
      final response = await _client.rpc('dashboard_station_fuel_status');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load station fuel status: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getMotorcycleRejections() async {
    try {
      final response = await _client.rpc('dashboard_motorcycle_rejections');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load motorcycle rejections: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getStationIntelligence() async {
    try {
      final response = await _client
          .from('admin_station_intelligence_dashboard')
          .select(
            'filling_station_id, filling_station_name, '
            'district_id, district_name, region, omc, '
            'latitude, longitude, licence_number, '
            'operational_status, active, dealer_contact_details, '
            'location_description, '
            'current_petrol_litres, petrol_stock_status, '
            'petrol_stock_last_updated, '
            'current_diesel_litres, diesel_stock_status, '
            'diesel_stock_last_updated, '
            'last_petrol_received_at, last_petrol_received_litres, '
            'last_diesel_received_at, last_diesel_received_litres',
          )
          .order('filling_station_name');

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load station intelligence: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getStationConsumption() async {
    try {
      final response = await _client
          .from('admin_station_consumption_dashboard')
          .select(
            'filling_station_id, product, valid_intervals, '
            'observed_consumption_litres, observed_days, '
            'estimated_daily_consumption_litres, '
            'consumption_data_status, '
            'observation_started_at, observation_ended_at',
          );

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load station consumption: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getStationRejections() async {
    try {
      final response = await _client
          .from('admin_station_rejection_dashboard')
          .select(
            'filling_station_id, total_attempts, rejection_count, '
            'already_fueled_count, identifier_conflict_count, '
            'invalid_count, last_rejection_at',
          )
          .order('rejection_count', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load station rejection intelligence: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getRegionalFuelReceipts() async {
    try {
      final response = await _client
          .from('admin_regional_fuel_receipts_dashboard')
          .select(
            'region, product, receipt_count, stations_receiving, '
            'total_received_litres, latest_receipt_at',
          )
          .order('total_received_litres', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load regional fuel receipts: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getFuelingActivity({
    DateTime? date,
  }) async {
    try {
      final selectedDate = date ?? DateTime.now();

      // MERA Fuel Control operates on Malawi calendar dates.
      // Malawi uses UTC+2 throughout the year.
      final startOfMalawiDayUtc = DateTime.utc(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      ).subtract(const Duration(hours: 2));

      final endOfMalawiDayUtc = startOfMalawiDayUtc.add(
        const Duration(days: 1),
      );

      final response = await _client
          .from('admin_fueling_activity_dashboard')
          .select(
            'fueling_id, fueled_at, vehicle_id, vehicle_code, '
            'plate_number, driver_id, driver_id_number, fuel_type, '
            'quantity_litres, attendant_id, device_id, '
            'quantity_litres, attendant_id, attendant_staff_number, '
            'attendant_name, attendant_role, device_id, '
            'identification_method, override_used, override_reason, '
            'sync_conflict, conflict_with_fueling_id, conflict_reason, '
            'conflict_detected_at, restriction_type_at_fueling, '
            'restriction_hours_at_fueling, filling_station_id, '
            'filling_station_name, district_id, district_name, '
            'region, omc',
          )
          .gte('fueled_at', startOfMalawiDayUtc.toIso8601String())
          .lt('fueled_at', endOfMalawiDayUtc.toIso8601String())
          .order('fueled_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Unable to load fueling activity: $error');
    }
  }

Future<List<Map<String, dynamic>>> getFuelingAnalytics({
  required DateTime startDate,
  required DateTime endDate,
}) async {
  try {
    // Dates supplied by the Analytics page represent Malawi calendar dates.
    // Malawi is UTC+2 throughout the year.
    final startOfMalawiPeriodUtc = DateTime.utc(
      startDate.year,
      startDate.month,
      startDate.day,
    ).subtract(const Duration(hours: 2));

    // endDate is inclusive from the user's perspective, therefore move
    // to the start of the following Malawi calendar day.
    final endOfMalawiPeriodUtc = DateTime.utc(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1)).subtract(const Duration(hours: 2));

    const pageSize = 1000;
    var from = 0;

    final allRows = <Map<String, dynamic>>[];

    while (true) {
      final response = await _client
          .rpc(
            'dashboard_fueling_analytics',
            params: {
              'p_start_at': startOfMalawiPeriodUtc.toIso8601String(),
              'p_end_at': endOfMalawiPeriodUtc.toIso8601String(),
            },
          )
          .range(from, from + pageSize - 1);

      final page = List<Map<String, dynamic>>.from(response);

      allRows.addAll(page);

      // A partial page means there are no more records.
      if (page.length < pageSize) {
        break;
      }

      from += pageSize;
    }

    return allRows;
  } catch (error) {
    throw Exception('Unable to load fueling analytics: $error');
  }
}
}
