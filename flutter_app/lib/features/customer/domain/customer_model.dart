class CustomerModel {
  final String id;
  final String name;
  final String? phone;
  final double creditLimit;
  final double overdueAmount;
  final DateTime createdAt;

  CustomerModel({
    required this.id,
    required this.name,
    this.phone,
    required this.creditLimit,
    required this.overdueAmount,
    required this.createdAt,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      creditLimit: (json['credit_limit'] as num).toDouble(),
      overdueAmount: (json['overdue_amount'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
