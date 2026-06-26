import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

final pendingRepositoryProvider = Provider<PendingRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PendingRepository(dio);
});

class PendingRepository {
  final Dio _dio;

  PendingRepository(this._dio);

  /// Fetch list of pending stock adjustments
  Future<List<Map<String, dynamic>>> fetchPendingAdjustments() async {
    final response = await _dio.get(ApiEndpoints.pending);
    final list = response.data as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Approve a pending stock adjustment
  Future<Map<String, dynamic>> approveAdjustment(String id) async {
    final response = await _dio.post(ApiEndpoints.approveAdjustment(id));
    return response.data as Map<String, dynamic>;
  }

  /// Reject a pending stock adjustment
  Future<Map<String, dynamic>> rejectAdjustment(String id) async {
    final response = await _dio.post(ApiEndpoints.rejectAdjustment(id));
    return response.data as Map<String, dynamic>;
  }
}
