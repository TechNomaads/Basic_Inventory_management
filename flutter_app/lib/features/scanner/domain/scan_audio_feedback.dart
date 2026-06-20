import 'package:audioplayers/audioplayers.dart';

/// Provides mode-specific audio feedback for scan events.
///
/// Uses short audio cues to give the cashier/staff instant confirmation
/// without needing to look at the screen:
///   - Billing beep: item added to cart
///   - Inventory chime: product recognized
///   - Error buzz: scan rejected (out of stock, unknown barcode, etc.)
class ScanAudioFeedback {
  static final AudioPlayer _player = AudioPlayer();

  ScanAudioFeedback._();

  /// Short beep — billing mode, successful cart addition.
  static Future<void> playBillingBeep() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/billing_beep.wav'));
    } catch (_) {
      // Silently ignore audio errors — feedback is non-critical
    }
  }

  /// Chime — inventory mode, product recognized.
  static Future<void> playInventoryChime() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/inventory_chime.wav'));
    } catch (_) {}
  }

  /// Buzz — any mode, scan rejected (error).
  static Future<void> playErrorBuzz() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/error_buzz.wav'));
    } catch (_) {}
  }

  /// Release the audio player resources.
  static Future<void> dispose() async {
    await _player.dispose();
  }
}
