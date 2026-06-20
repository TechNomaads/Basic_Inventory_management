/// Centralized debounce + deduplication logic for barcode scanning.
///
/// Prevents rapid-fire duplicate scans from a single barcode remaining
/// in the camera's field of view, and enforces a minimum cooldown
/// between any two accepted scans.
class BarcodeDebouncer {
  /// Minimum time between any two accepted scans, regardless of barcode value.
  final Duration cooldown;

  /// Window during which the same barcode string is rejected as a duplicate.
  final Duration dedupeWindow;

  DateTime? _lastAcceptedTime;
  final Map<String, DateTime> _recentBarcodes = {};

  BarcodeDebouncer({
    this.cooldown = const Duration(milliseconds: 800),
    this.dedupeWindow = const Duration(seconds: 3),
  });

  /// Returns `true` if the barcode should be accepted for processing.
  ///
  /// Returns `false` if:
  ///   - Any scan was accepted less than [cooldown] ago (global rate-limit)
  ///   - The same [barcode] was accepted less than [dedupeWindow] ago
  bool shouldAccept(String barcode) {
    final now = DateTime.now();

    // 1. Global cooldown — reject if too soon after last accepted scan
    if (_lastAcceptedTime != null &&
        now.difference(_lastAcceptedTime!) < cooldown) {
      return false;
    }

    // 2. Same-barcode dedup — reject if this barcode was recently accepted
    final lastSeen = _recentBarcodes[barcode];
    if (lastSeen != null && now.difference(lastSeen) < dedupeWindow) {
      return false;
    }

    // Accept this scan
    _lastAcceptedTime = now;
    _recentBarcodes[barcode] = now;
    _cleanup(now);
    return true;
  }

  /// Remove expired entries from the recent barcodes map.
  void _cleanup(DateTime now) {
    _recentBarcodes.removeWhere(
      (_, timestamp) => now.difference(timestamp) > dedupeWindow,
    );
  }

  /// Reset all state (e.g. when switching scanner modes).
  void reset() {
    _lastAcceptedTime = null;
    _recentBarcodes.clear();
  }
}
