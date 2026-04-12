/// Number and date formatters.

import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final _dateFormat = DateFormat('dd MMM yyyy');
  static final _dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm');
  static final _timeFormat = DateFormat('HH:mm');

  static String currency(double? value) {
    if (value == null) return '-';
    return _currencyFormat.format(value);
  }

  static String date(DateTime? dt) {
    if (dt == null) return '-';
    return _dateFormat.format(dt.toLocal());
  }

  static String dateTime(DateTime? dt) {
    if (dt == null) return '-';
    return _dateTimeFormat.format(dt.toLocal());
  }

  static String time(DateTime? dt) {
    if (dt == null) return '-';
    return _timeFormat.format(dt.toLocal());
  }

  static String quantity(int qty) {
    return NumberFormat('#,###').format(qty);
  }

  /// Format a quantity change with sign: "+50" or "-30"
  static String delta(int change) {
    return change > 0 ? '+$change' : '$change';
  }
}
