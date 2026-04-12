/// Input validators for forms.

class Validators {
  Validators._();

  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final regex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!regex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? barcode(String? value) {
    if (value == null || value.trim().isEmpty) return 'Barcode is required';
    if (value.length < 3) return 'Barcode must be at least 3 characters';
    return null;
  }

  static String? quantity(String? value) {
    if (value == null || value.isEmpty) return 'Quantity is required';
    final num = int.tryParse(value);
    if (num == null) return 'Must be a number';
    if (num < 1 || num > 999) return 'Must be between 1 and 999';
    return null;
  }
}
