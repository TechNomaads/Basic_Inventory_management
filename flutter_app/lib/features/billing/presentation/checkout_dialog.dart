import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/billing_notifier.dart';

class CheckoutDialog extends ConsumerStatefulWidget {
  const CheckoutDialog({super.key});

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  late final TextEditingController _amountPaidController;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    final initialAmount = cart.amountPaid ?? cart.totalAmount;
    _amountPaidController = TextEditingController(text: initialAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = cart.totalAmount;
    
    // Parse current input amount
    final inputVal = double.tryParse(_amountPaidController.text) ?? total;
    final remaining = total - inputVal;
    
    // Validate checkout conditions
    bool isCreditLimitExceeded = false;
    bool isWalkinUnpaid = false;
    double projectedDebt = 0.0;

    if (cart.customerPhone.isNotEmpty) {
      projectedDebt = cart.customerOverdue + (remaining > 0 ? remaining : 0.0);
      if (projectedDebt > cart.customerCreditLimit) {
        isCreditLimitExceeded = true;
      }
    } else {
      // Walk-in customer
      if (remaining > 0.01) { // allow tiny float epsilon
        isWalkinUnpaid = true;
      }
    }

    final bool isCheckoutBlocked = isCreditLimitExceeded || isWalkinUnpaid;

    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Center(
        child: Text(
          'Complete Payment',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      content: cart.isLoading
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 24),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing transaction...', style: TextStyle(color: AppColors.textSecondary)),
                SizedBox(height: 24),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Error display
                  if (cart.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Text(
                        cart.errorMessage!,
                        style: GoogleFonts.inter(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Total Summary
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'Total Payable Amount',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Select Payment Mode
                  Text(
                    'Select Payment Method',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PaymentTile(
                          label: 'Cash',
                          icon: Icons.payments_outlined,
                          isSelected: cart.paymentMode == 'cash',
                          onTap: () => ref.read(cartProvider.notifier).setPaymentMode('cash'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PaymentTile(
                          label: 'UPI',
                          icon: Icons.qr_code_outlined,
                          isSelected: cart.paymentMode == 'upi',
                          onTap: () => ref.read(cartProvider.notifier).setPaymentMode('upi'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PaymentTile(
                          label: 'Card',
                          icon: Icons.credit_card_outlined,
                          isSelected: cart.paymentMode == 'card',
                          onTap: () => ref.read(cartProvider.notifier).setPaymentMode('card'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Amount Paid Input Box
                  Text(
                    'Amount Paid (₹)',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountPaidController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Enter amount paid',
                      filled: true,
                      fillColor: AppColors.surfaceBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {});
                      final parsed = double.tryParse(val);
                      ref.read(cartProvider.notifier).setAmountPaid(parsed);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Remaining / Excess Display
                  if (remaining > 0.01)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.stockAmber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Remaining Due:', style: TextStyle(color: AppColors.stockAmber, fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('₹${remaining.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.stockAmber, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )
                  else if (remaining < -0.01)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Change / Credit Adjustment:', style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('₹${remaining.abs().toStringAsFixed(2)}', style: const TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Customer info & warnings
                  if (cart.customerName.isNotEmpty || cart.customerPhone.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_pin_outlined, color: AppColors.textSecondary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Customer: ${cart.customerName}',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Credit Limit:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint)),
                              Text('₹${cart.customerCreditLimit.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Current Overdue:', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textHint)),
                              Text('₹${cart.customerOverdue.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.stockRed)),
                            ],
                          ),
                          if (remaining > 0.01) ...[
                            const Divider(color: AppColors.divider, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Projected Total Debt:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                                Text('₹${projectedDebt.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isCreditLimitExceeded ? AppColors.stockRed : AppColors.textPrimary)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // BLOCK Warning Displays
                  if (isCreditLimitExceeded) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.stockRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.stockRed.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.stockRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Purchase exceeds credit limit!',
                              style: GoogleFonts.inter(color: AppColors.stockRed, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isWalkinUnpaid) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.stockRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.stockRed.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.stockRed, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Walk-in customer must pay the net total amount in full.',
                              style: GoogleFonts.inter(color: AppColors.stockRed, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: cart.isLoading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isCheckoutBlocked
                    ? null
                    : () async {
                        final success = await ref.read(cartProvider.notifier).processCheckout();
                        if (success && context.mounted) {
                          // Close dialog and bottom sheet, then navigate
                          Navigator.pop(context); // Close dialog
                          Navigator.pop(context); // Close CartSheet
                          context.push('/billing/success');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCheckoutBlocked ? AppColors.surfaceBg : AppColors.primary,
                ),
                child: const Text('CONFIRM PAYMENT'),
              ),
            ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.12) : AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
