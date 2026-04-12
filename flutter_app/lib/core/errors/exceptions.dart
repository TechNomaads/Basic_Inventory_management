/// Custom exception types mapped to HTTP error codes.

class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({required this.message, this.statusCode});
}

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException({this.message = 'Unauthorized'});
}

class ForbiddenException implements Exception {
  final String message;
  const ForbiddenException({this.message = 'Forbidden'});
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException({this.message = 'Not found'});
}

class ConflictException implements Exception {
  final String message;
  const ConflictException({this.message = 'Version conflict'});
}
