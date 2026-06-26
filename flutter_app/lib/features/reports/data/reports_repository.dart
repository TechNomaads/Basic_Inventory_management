import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ReportsRepository(dio);
});

class ReportsRepository {
  final Dio _dio;

  ReportsRepository(this._dio);

  /// Fetch dashboard summary metrics
  Future<Map<String, dynamic>> fetchSummary({String? locationId}) async {
    final Map<String, dynamic> queryParams = {};
    if (locationId != null && locationId.isNotEmpty) {
      queryParams['location_id'] = locationId;
    }
    final response = await _dio.get(
      ApiEndpoints.reportsSummary,
      queryParameters: queryParams,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetch daily sales trend data (revenue and profit) for the last 7 days
  Future<List<Map<String, dynamic>>> fetchSalesTrend({String? locationId}) async {
    final Map<String, dynamic> queryParams = {};
    if (locationId != null && locationId.isNotEmpty) {
      queryParams['location_id'] = locationId;
    }
    final response = await _dio.get(
      ApiEndpoints.reportsSalesTrend,
      queryParameters: queryParams,
    );
    final list = response.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch inventory stock distribution aggregated by product category
  Future<List<Map<String, dynamic>>> fetchCategoryStock({String? locationId}) async {
    final Map<String, dynamic> queryParams = {};
    if (locationId != null && locationId.isNotEmpty) {
      queryParams['location_id'] = locationId;
    }
    final response = await _dio.get(
      ApiEndpoints.reportsCategoryStock,
      queryParameters: queryParams,
    );
    final list = response.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Fetch recent transactions list
  Future<Map<String, dynamic>> fetchTransactions({
    int page = 1,
    int size = 10,
    String? type,
    String? productId,
  }) async {
    final Map<String, dynamic> queryParams = {
      'page': page,
      'size': size,
      if (productId != null) 'product_id': productId,
    };
    if (type != null) {
      queryParams['type'] = type;
    }
    final response = await _dio.get(
      ApiEndpoints.reportsTransactions,
      queryParameters: queryParams,
    );
    return response.data as Map<String, dynamic>;
  }
}
