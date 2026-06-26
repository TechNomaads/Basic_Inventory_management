import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/billing_notifier.dart';

class InvoiceSuccessScreen extends ConsumerWidget {
  const InvoiceSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final invoice = cart.invoice;

    if (invoice == null) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'No transaction details found.',
                style: GoogleFonts.outfit(color: AppColors.textPrimary, fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final items = invoice['items'] as List<dynamic>? ?? [];
    final invoiceNum = invoice['invoice_number'] as String? ?? 'N/A';
    final customerName = invoice['customer_name'] as String? ?? 'Walk-in Customer';
    final customerPhone = invoice['customer_phone'] as String? ?? '';
    final totalAmount = (invoice['total_amount'] as num? ?? 0).toDouble();
    final subtotal = (invoice['subtotal'] as num? ?? 0).toDouble();
    final taxAmount = (invoice['tax_amount'] as num? ?? 0).toDouble();
    final discountAmount = (invoice['discount_amount'] as num? ?? 0).toDouble();
    final paymentMode = (invoice['payment_mode'] as String? ?? 'CASH').toUpperCase();
    final locationName = invoice['location_name'] as String? ?? 'Main Warehouse';
    final userName = invoice['user_name'] as String? ?? 'System Operator';
    
    final dateString = invoice['created_at'] != null 
        ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(invoice['created_at'] as String))
        : DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Success Header ─────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Checkout Complete!',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stock levels updated successfully',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Premium Paper Receipt Card ─────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Receipt Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        children: [
                          Text(
                            locationName,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'OPERATOR: $userName',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textHint,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    _buildDottedDivider(),

                    // Tx Metadata
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildReceiptMetadataRow('Invoice No.', invoiceNum),
                          const SizedBox(height: 6),
                          _buildReceiptMetadataRow('Date & Time', dateString),
                          const SizedBox(height: 6),
                          _buildReceiptMetadataRow('Payment Mode', paymentMode),
                          const SizedBox(height: 6),
                          _buildReceiptMetadataRow('Customer', customerPhone.isNotEmpty ? '$customerName ($customerPhone)' : customerName),
                        ],
                      ),
                    ),

                    _buildDottedDivider(),

                    // Items List Table
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ITEMS SOLD',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final prodName = item['product_name'] as String? ?? 'Product';
                              final qty = item['quantity'] as int? ?? 1;
                              final unitPrice = (item['unit_price'] as num? ?? 0).toDouble();
                              final lineTotal = (item['line_total'] as num? ?? 0).toDouble();

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prodName,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '$qty x ₹${unitPrice.toStringAsFixed(2)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₹${lineTotal.toStringAsFixed(2)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    _buildDottedDivider(),

                    // Totals
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildReceiptTotalsRow('Subtotal (Exclusive)', '₹${subtotal.toStringAsFixed(2)}'),
                          const SizedBox(height: 6),
                          _buildReceiptTotalsRow('Taxes Added', '₹${taxAmount.toStringAsFixed(2)}'),
                          if (discountAmount > 0) ...[
                            const SizedBox(height: 6),
                            _buildReceiptTotalsRow('Discount Applied', '-₹${discountAmount.toStringAsFixed(2)}', color: AppColors.stockRed),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'TOTAL PAID',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '₹${totalAmount.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Receipt Footer Message
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceBg,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Center(
                        child: Text(
                          '*** Thank you for shopping with us! ***',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textHint,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // ── Action Buttons ─────────────────────────────────
              ElevatedButton.icon(
                icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
                label: const Text('NEW TRANSACTION'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  ref.read(cartProvider.notifier).clearCart();
                  context.pop(); // Pop success screen back to BillingScreen
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  ref.read(cartProvider.notifier).clearCart();
                  context.go('/dashboard'); // Go directly back to main dashboard
                },
                child: const Text('BACK TO DASHBOARD'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptMetadataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textHint,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptTotalsRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDottedDivider() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.divider),
              ),
            );
          }),
        );
      },
    );
  }
}
