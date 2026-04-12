/// Failure types for the Either pattern.
///
/// All API calls return Either<Failure, T>. Failures carry
/// a user-friendly message for direct display.

class Failure {
  final String message;
  final int? statusCode;

  const Failure({required this.message, this.statusCode});

  @override
  String toString() => 'Failure($statusCode: $message)';
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.statusCode});
}

class NetworkFailure extends Failure {
  const NetworkFailure({super.message = 'Network error. Check your connection.'});
}

class CacheFailure extends Failure {
  const CacheFailure({super.message = 'Local cache error.'});
}

class AuthFailure extends Failure {
  const AuthFailure({super.message = 'Authentication failed.'});
}

class ConflictFailure extends Failure {
  const ConflictFailure({
    super.message = 'This item was updated by another user. Please refresh.',
    super.statusCode = 409,
  });
}
