/// [UserModel] — Represents an authenticated user.
///
/// Responsibilities:
///   - Parse user data from JWT and API responses
///   - Provide role checking utilities

class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool isActive;
  final List<String> locationIds;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.locationIds = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      isActive: json['is_active'] as bool? ?? true,
      locationIds: (json['location_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isStaff => role == 'staff';
  bool get isViewer => role == 'viewer';
  bool get canManage => isAdmin || isManager;
}

/// User roles enum for role guard comparisons
enum UserRole { admin, manager, staff, viewer }
