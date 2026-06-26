import 'customer_model.dart';

class CustomerInvoiceModel {
  final String id;
  final String invoiceNumber;
  final String locationName;
  final DateTime createdAt;
  final double totalAmount;
  final double amountPaid;
  final String paymentMode;

  CustomerInvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.locationName,
    required this.createdAt,
    required this.totalAmount,
    required this.amountPaid,
    required this.paymentMode,
  });

  factory CustomerInvoiceModel.fromJson(Map<String, dynamic> json) {
    return CustomerInvoiceModel(
      id: json['id'] as String,
      invoiceNumber: json['invoice_number'] as String,
      locationName: json['location_name'] as String? ?? 'N/A',
      createdAt: DateTime.parse(json['created_at'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      amountPaid: (json['amount_paid'] as num? ?? json['total_amount'] as num).toDouble(),
      paymentMode: json['payment_mode'] as String? ?? 'CASH',
    );
  }

  double get remainingDue => totalAmount - amountPaid;
}

class CustomerDetailModel {
  final CustomerModel profile;
  final List<CustomerInvoiceModel> invoices;

  CustomerDetailModel({
    required this.profile,
    required this.invoices,
  });

  factory CustomerDetailModel.fromJson(Map<String, dynamic> json) {
    final list = json['invoices'] as List<dynamic>? ?? [];
    return CustomerDetailModel(
      profile: CustomerModel.fromJson(json),
      invoices: list.map((e) => CustomerInvoiceModel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
