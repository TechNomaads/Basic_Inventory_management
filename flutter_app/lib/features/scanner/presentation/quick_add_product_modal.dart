import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/cache_sync_service.dart';

/// Inline bottom sheet for creating a new product when an unknown barcode
/// is scanned in Inventory mode.
///
/// Shows minimal fields for rapid entry without leaving the scanner flow:
///   - Product Name (required)
///   - Sell Price (required)
///   - Cost Price (optional)
///   - Category dropdown (optional)
///   - Unit dropdown (optional)
class QuickAddProductModal extends ConsumerStatefulWidget {
  final String barcode;

  const QuickAddProductModal({super.key, required this.barcode});

  @override
  ConsumerState<QuickAddProductModal> createState() =>
      _QuickAddProductModalState();
}

class _QuickAddProductModalState extends ConsumerState<QuickAddProductModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  String _selectedUnit = 'pcs';
  bool _isLoading = false;
  String? _error;

  static const List<String> _units = ['pcs', 'kg', 'g', 'ltr', 'ml', 'box', 'pack', 'pair'];

  @override
  void dispose() {
    _nameController.dispose();
    _sellPriceController.dispose();
    _costPriceController.dispose();
    super.dispose();
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dio = ref.read(dioProvider);

      // Generate a simple SKU from the barcode
      final sku = 'SKU-${widget.barcode}';

      final response = await dio.post(
        ApiEndpoints.products,
        data: {
          'barcode': widget.barcode,
          'name': _nameController.text.trim(),
          'sku': sku,
          'sell_price': double.parse(_sellPriceController.text.trim()),
          'cost_price': _costPriceController.text.trim().isNotEmpty
              ? double.parse(_costPriceController.text.trim())
              : null,
          'unit': _selectedUnit,
          'tax_rate': 18.0,
        },
      );

      final data = response.data as Map<String, dynamic>;

      // Cache the newly created product in Drift
      final dao = ref.read(productCacheDaoProvider);
      await dao.upsertProduct(data);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Product '${_nameController.text.trim()}' created!"),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } on DioException catch (e) {
      final msg =
          e.response?.data?['detail']?.toString() ?? 'Failed to create product.';
      setState(() {
        _isLoading = false;
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_box_rounded,
                        color: AppColors.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Barcode Detected',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.barcode,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Product name (required)
              TextFormField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
                decoration: _inputDecoration('Product Name *', Icons.label_outline),
              ),
              const SizedBox(height: 12),

              // Sell price + Cost price row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sellPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      style: const TextStyle(color: AppColors.textPrimary),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (double.tryParse(v.trim()) == null) return 'Invalid';
                        return null;
                      },
                      decoration:
                          _inputDecoration('Sell Price ₹ *', Icons.sell_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration:
                          _inputDecoration('Cost Price ₹', Icons.price_change_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Unit dropdown
              DropdownButtonFormField<String>(
                value: _selectedUnit,
                dropdownColor: AppColors.cardBg,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration('Unit', Icons.straighten_outlined),
                items: _units
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedUnit = v);
                },
              ),
              const SizedBox(height: 16),

              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style:
                        GoogleFonts.inter(color: AppColors.error, fontSize: 13),
                  ),
                ),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Skip',
                        style: GoogleFonts.outfit(
                            color: AppColors.textSecondary, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitProduct,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save & Continue',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textHint),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: AppColors.surfaceBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
