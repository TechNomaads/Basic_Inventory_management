/// App-wide colour palette.
///
/// Uses a dark warehouse-optimized theme with high contrast
/// for scanning in low-light environments.
///
/// Dependencies: Flutter material

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary palette ───────────────────────────────────────────
  static const Color primary = Color(0xFF1A73E8);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryLight = Color(0xFF4FC3F7);
  static const Color accent = Color(0xFF00BFA5);

  // ── Background ────────────────────────────────────────────────
  static const Color scaffoldBg = Color(0xFF0F1117);
  static const Color cardBg = Color(0xFF1A1D27);
  static const Color surfaceBg = Color(0xFF252836);
  static const Color bottomNavBg = Color(0xFF1A1D27);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB0B3C6);
  static const Color textHint = Color(0xFF6B6F82);

  // ── Status colours (stock levels) ─────────────────────────────
  static const Color stockGreen = Color(0xFF4CAF50);
  static const Color stockAmber = Color(0xFFFFC107);
  static const Color stockRed = Color(0xFFE53935);

  // ── Scanner overlay ───────────────────────────────────────────
  static const Color scanOverlay = Color(0x99000000);
  static const Color scanCorner = Color(0xFF00E5FF);

  // ── Misc ──────────────────────────────────────────────────────
  static const Color divider = Color(0xFF2A2D3A);
  static const Color error = Color(0xFFCF6679);
  static const Color success = Color(0xFF69F0AE);
  static const Color warning = Color(0xFFFFD54F);
}
