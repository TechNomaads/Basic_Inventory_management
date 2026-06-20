import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return BillingRepository(dio);
});

class BillingRepository {
  final Dio _dio;

  BillingRepository(this._dio);

  /// Fetch product info by barcode
  Future<Map<String, dynamic>> fetchProductByBarcode(String barcode) async {
    final response = await _dio.get(ApiEndpoints.productByBarcode(barcode));
    return response.data as Map<String, dynamic>;
  }

  /// Fetch store locations
  Future<List<Map<String, dynamic>>> fetchLocations() async {
    final response = await _dio.get(ApiEndpoints.locationsMeta);
    final list = response.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch all inventory items at a location (used to map version and available stock)
  Future<List<Map<String, dynamic>>> fetchInventoryByLocation(String locationId) async {
    final response = await _dio.get(ApiEndpoints.inventoryByLocation(locationId));
    final list = response.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Perform sales checkout
  Future<Map<String, dynamic>> checkout(Map<String, dynamic> data) async {
    final response = await _dio.post(ApiEndpoints.checkout, data: data);
    return response.data as Map<String, dynamic>;
  }

  /// Look up customer profile by phone number
  Future<Map<String, dynamic>?> lookupCustomer(String phone) async {
    try {
      final response = await _dio.get(ApiEndpoints.customerLookup(phone));
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // Customer not found is normal, we will create one
      }
      rethrow;
    }
  }

  /// Fetch daily sales metrics summary
  Future<Map<String, dynamic>> fetchDailySummary({String? locationId}) async {
    final Map<String, dynamic> queryParameters = {};
    if (locationId != null) {
      queryParameters['location_id'] = locationId;
    }
    final response = await _dio.get(
      ApiEndpoints.dailySalesSummary,
      queryParameters: queryParameters,
    );
    return response.data as Map<String, dynamic>;
  }
}
