import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return AuditRepository(dio);
});

class AuditRepository {
  final Dio _dio;

  AuditRepository(this._dio);

  /// Fetch paginated audit log list
  Future<Map<String, dynamic>> fetchAuditLogs({
    String? action,
    int skip = 0,
    int limit = 50,
  }) async {
    final Map<String, dynamic> queryParams = {
      'skip': skip,
      'limit': limit,
    };
    if (action != null && action.isNotEmpty) {
      queryParams['action'] = action;
    }

    final response = await _dio.get(
      ApiEndpoints.audit,
      queryParameters: queryParams,
    );

    return response.data as Map<String, dynamic>;
  }
}
