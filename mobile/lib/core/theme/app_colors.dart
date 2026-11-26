import 'package:flutter/material.dart';

/// Colour tokens for the "Calm Clinical" look: soft grey-green background,
/// dark green-black text, teal actions, and one colour per information source.
/// Text colours are chosen to keep 4.5:1 contrast on every surface and tint below.
abstract final class AppColors {
  // Brand
  static const primary = Color(0xFF0B6B63); // buttons, active tab, links
  static const primaryDark = Color(0xFF085850); // pressed state
  static const primaryTint = Color(0xFFDCEDE9); // icon tiles, selected nav pill
  static const violet = Color(0xFF5B47C9);
  static const violetTint = Color(0xFFEFECFB);

  /// Dark teal cards (patient header, personalised counselling card).
  static const navyCard = Color(0xFF0F5C56);
  static const onNavyMuted = Color(0xFFCFE5E1);
  static const onNavyAccent = Color(0xFFA7DAD2);

  /// Kept for widgets that used a gradient; the design uses one solid colour.
  static const heroGradient = LinearGradient(colors: [navyCard, navyCard]);

  // Text
  static const navy = Color(0xFF14302B); // headings
  static const ink = Color(0xFF1B3833); // strong body text
  static const body = Color(0xFF3D5650);
  static const muted = Color(0xFF4A635D);

  // Surfaces
  static const background = Color(0xFFF4F7F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFE4ECEA); // segmented track, info boxes
  static const border = Color(0xFFDCE5E3);
  static const borderStrong = Color(0xFFC9D6D3);
  static const launch = Color(0xFF0F5C56); // splash / end screen

  // Status (dark text on light tint)
  static const success = Color(0xFF256B3A);
  static const successTint = Color(0xFFE3F1E6);
  static const pending = Color(0xFF8A5300);
  static const pendingTint = Color(0xFFFBEFD9);
  static const error = Color(0xFFB42318);
  static const errorTint = Color(0xFFFCEBEA);
  static const errorBorder = Color(0xFFEDC5C1);

  // Information source — keeps AI output visibly separate from doctor decisions
  static const ai = Color(0xFF5B47C9);
  static const aiTint = Color(0xFFEFECFB);
  static const doctor = Color(0xFF256B3A);
  static const doctorTint = Color(0xFFE3F1E6);
  static const admin = Color(0xFF4A5568);
  static const adminTint = Color(0xFFECEDF0);

  // Development-only markers
  static const dev = Color(0xFF8A5A00);
  static const devTint = Color(0xFFFFF4D6);
}
