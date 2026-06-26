import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/validators.dart';
import '../../product/data/product_repository.dart';

class AddEditProductScreen extends ConsumerStatefulWidget {
  final String? productId;

  const AddEditProductScreen({super.key, this.productId});

  @override
  ConsumerState<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends ConsumerState<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _costController = TextEditingController();
  final _sellController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  bool get isEditing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadProductDetails();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _sellController.dispose();
    super.dispose();
  }

  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(productRepositoryProvider);
      final product = await repo.fetchProductById(widget.productId!);
      
      setState(() {
        _nameController.text = product['name'] as String? ?? '';
        _barcodeController.text = product['barcode'] as String? ?? '';
        _skuController.text = product['sku'] as String? ?? '';
        _costController.text = (product['cost_price'] as num?)?.toString() ?? '';
        _sellController.text = (product['sell_price'] as num?)?.toString() ?? '';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load product details: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final payload = {
      'name': _nameController.text.trim(),
      'barcode': _barcodeController.text.trim(),
      'sku': _skuController.text.trim(),
      'cost_price': double.tryParse(_costController.text.trim()),
      'sell_price': double.tryParse(_sellController.text.trim()),
      'unit': 'pcs',
    };

    try {
      final repo = ref.read(productRepositoryProvider);
      if (isEditing) {
        await repo.updateProduct(widget.productId!, payload);
      } else {
        await repo.createProduct(payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Product updated successfully.' : 'Product created successfully.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } catch (e) {
      setState(() {
        _errorMessage = 'Submission failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: Text(isEditing ? AppStrings.editProduct : AppStrings.addProduct),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading && _nameController.text.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.stockRed, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildField('Product Name *', _nameController,
                        validator: (v) => Validators.required(v, field: 'Name')),
                    const SizedBox(height: 12),
                    _buildField('Barcode *', _barcodeController,
                        validator: Validators.barcode),
                    const SizedBox(height: 12),
                    _buildField('SKU *', _skuController,
                        validator: (v) => Validators.required(v, field: 'SKU')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField('Cost Price (₹) *', _costController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => Validators.required(v, field: 'Cost Price')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField('Sell Price (₹) *', _sellController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) => Validators.required(v, field: 'Sell Price')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSubmit,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                isEditing ? 'Update Product' : 'Create Product',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
