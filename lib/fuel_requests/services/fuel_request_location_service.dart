
import 'package:supabase_flutter/supabase_flutter.dart';

class FuelRequestLocationService {
  FuelRequestLocationService();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getDistricts() async {
    final response = await _supabase
        .from('districts')
        .select('id, name')
        .eq('active', true)
        .order('name');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getStations({
    required String districtId,
    String? omcId,
  }) async {
    final response = await _supabase.rpc(
      'get_fuel_request_stations',
      params: {
        'p_district_id': districtId,
        'p_omc_id': omcId,
      },
    );

    return List<Map<String, dynamic>>.from(response as List);
  }


Future<List<Map<String, dynamic>>> getOmcsForDistrict(
  String districtId,
) async {
  final stations = await getStations(
    districtId: districtId,
  );

  // Get OMC IDs from eligible filling stations.
  final availableOmcIds = stations
      .map((station) => station['omc_id']?.toString())
      .whereType<String>()
      .toSet();

  final response = await _supabase
      .from('omcs')
      .select('id, name')
      .eq('active', true)
      .order('name');

  final omcs = List<Map<String, dynamic>>.from(response);

  return omcs.where((omc) {
    return availableOmcIds.contains(omc['id']?.toString());
  }).toList();
}

}
