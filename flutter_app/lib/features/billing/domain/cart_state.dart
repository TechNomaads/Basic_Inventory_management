import 'cart_item.dart';

class CartState {
  final List<CartItem> items;
  final String customerName;
  final String customerPhone;
  final String paymentMode; // cash, card, upi
  final double discountAmount;
  final String notes;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, dynamic>? invoice; // holds response on successful checkout
  final double? amountPaid;
  final double customerCreditLimit;
  final double customerOverdue;

  const CartState({
    this.items = const [],
    this.customerName = '',
    this.customerPhone = '',
    this.paymentMode = 'cash',
    this.discountAmount = 0.0,
    this.notes = '',
    this.isLoading = false,
    this.errorMessage,
    this.invoice,
    this.amountPaid,
    this.customerCreditLimit = 10000.0,
    this.customerOverdue = 0.0,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.subtotal);
  double get taxAmount => items.fold(0.0, (sum, item) => sum + item.taxAmount);
  double get totalAmount {
    final rawTotal = subtotal + taxAmount - discountAmount;
    return rawTotal < 0 ? 0.0 : rawTotal;
  }

  CartState copyWith({
    List<CartItem>? items,
    String? customerName,
    String? customerPhone,
    String? paymentMode,
    double? discountAmount,
    String? notes,
    bool? isLoading,
    String? errorMessage,
    Map<String, dynamic>? invoice,
    bool clearInvoice = false,
    double? amountPaid,
    bool clearAmountPaid = false,
    double? customerCreditLimit,
    double? customerOverdue,
  }) {
    return CartState(
      items: items ?? this.items,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      paymentMode: paymentMode ?? this.paymentMode,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      invoice: clearInvoice ? null : (invoice ?? this.invoice),
      amountPaid: clearAmountPaid ? null : (amountPaid ?? this.amountPaid),
      customerCreditLimit: customerCreditLimit ?? this.customerCreditLimit,
      customerOverdue: customerOverdue ?? this.customerOverdue,
    );
  }
}
