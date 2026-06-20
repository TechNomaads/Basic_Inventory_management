import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../domain/billing_notifier.dart';
import 'checkout_dialog.dart';

class CartSheet extends ConsumerStatefulWidget {
  const CartSheet({super.key});

  @override
  ConsumerState<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<CartSheet> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSearchingCustomer = false;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _phoneController.text = cart.customerPhone;
    _nameController.text = cart.customerName;
    if (cart.discountAmount > 0) {
      _discountController.text = cart.discountAmount.toString();
    }
    _notesController.text = cart.notes;

    // Set up phone listener for auto-lookup
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _nameController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() async {
    final phone = _phoneController.text.trim();
    if (phone.length == 10) {
      setState(() {
        _isSearchingCustomer = true;
      });
      final found = await ref.read(cartProvider.notifier).lookupCustomerPhone(phone);
      if (found && mounted) {
        final updatedCart = ref.read(cartProvider);
        _nameController.text = updatedCart.customerName;
        HapticFeedback.lightImpact();
      }
      if (mounted) {
        setState(() {
          _isSearchingCustomer = false;
        });
      }
    }
  }

  void _updateCartMetadata() {
    ref.read(cartProvider.notifier).setCustomerInfo(
          _nameController.text.trim(),
          _phoneController.text.trim(),
        );
    ref.read(cartProvider.notifier).setNotes(_notesController.text.trim());
    
    final discountVal = double.tryParse(_discountController.text) ?? 0.0;
    ref.read(cartProvider.notifier).setDiscount(discountVal);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final size = MediaQuery.of(context).size;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle Indicator
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Checkout Cart',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () {
                        _updateCartMetadata();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider),

              // Sliding items list and form inputs
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Items List ────────────────────────────────
                    Text(
                      'Cart Items (${cart.items.length})',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (cart.items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'Your cart is empty',
                            style: GoogleFonts.inter(color: AppColors.textHint),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cart.items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return Dismissible(
                            key: Key(item.productId),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.delete_outline, color: AppColors.error),
                            ),
                            onDismissed: (_) {
                              ref.read(cartProvider.notifier).removeProduct(item.productId);
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed ${item.name} from cart'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'SKU: ${item.sku} • BC: ${item.barcode}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Stock at store: ${item.stockQuantity} units',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: item.stockQuantity < 5
                                                ? AppColors.stockAmber
                                                : AppColors.stockGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₹${item.lineTotal.toStringAsFixed(2)}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '₹${item.sellPrice.toStringAsFixed(2)} + ${(item.taxRate).toStringAsFixed(0)}% Tax',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      
                                      // Stepper controls
                                      Row(
                                        children: [
                                          _QtyButton(
                                            icon: Icons.remove,
                                            onTap: () {
                                              ref.read(cartProvider.notifier).updateQuantity(
                                                    item.productId,
                                                    item.quantity - 1,
                                                  );
                                            },
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            child: Text(
                                              '${item.quantity}',
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          _QtyButton(
                                            icon: Icons.add,
                                            onTap: () {
                                              ref.read(cartProvider.notifier).updateQuantity(
                                                    item.productId,
                                                    item.quantity + 1,
                                                  );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),

                    // ── Customer Details Form ──────────────────────
                    Text(
                      'Customer Information',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Customer Phone',
                              labelStyle: const TextStyle(color: AppColors.textSecondary),
                              hintText: 'Enter 10-digit number...',
                              prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.textSecondary),
                              suffixIcon: _isSearchingCustomer
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nameController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'Customer Name',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              hintText: 'Enter full name...',
                              prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Discount & Notes ──────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Discount (₹)',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _discountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: '0.00',
                                  prefixIcon: Icon(Icons.local_offer_outlined, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Checkout Notes',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _notesController,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: 'Internal notes...',
                                  prefixIcon: Icon(Icons.notes_outlined, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Summary Totals Card ───────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _SummaryRow(label: 'Items Subtotal', value: '₹${cart.subtotal.toStringAsFixed(2)}'),
                          const SizedBox(height: 8),
                          _SummaryRow(label: 'Tax (GST 18% included)', value: '₹${cart.taxAmount.toStringAsFixed(2)}'),
                          if (double.tryParse(_discountController.text) != null &&
                              (double.tryParse(_discountController.text) ?? 0) > 0) ...[
                            const SizedBox(height: 8),
                            _SummaryRow(
                              label: 'Flat Discount',
                              value: '-₹${(double.tryParse(_discountController.text) ?? 0).toStringAsFixed(2)}',
                              valueColor: AppColors.stockRed,
                            ),
                          ],
                          const Divider(height: 24, color: AppColors.divider),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Payable',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              // Dynamically calculate total in real time
                              Builder(
                                builder: (context) {
                                  final disc = double.tryParse(_discountController.text) ?? 0.0;
                                  final total = (cart.subtotal + cart.taxAmount - disc) < 0
                                      ? 0.0
                                      : (cart.subtotal + cart.taxAmount - disc);
                                  return Text(
                                    '₹${total.toStringAsFixed(2)}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accent,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Proceed Button ────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () {
                                _updateCartMetadata();
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => const CheckoutDialog(),
                                );
                              },
                        child: Text(
                          'PROCEED TO PAYMENT',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surfaceBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 16),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
