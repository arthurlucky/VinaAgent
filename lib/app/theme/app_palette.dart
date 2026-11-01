import 'package:flutter/material.dart';

/// Brand palette for Vina Agent.
///
/// The identity is purple + light orange on white. Light mode uses a white
/// canvas with a deep violet primary and a soft orange secondary. Dark mode
/// keeps the same accents on a deep aubergine-black canvas.
class AppPalette {
  const AppPalette._();

  // ---- Dark mode (deep aubergine + violet + soft orange) ----
  static const Color darkBase = Color(0xFF0E0718);
  static const Color darkBaseAlt = Color(0xFF160C24);
  static const Color darkGlass = Color(0xFF1E1230);
  static const Color darkAccent = Color(0xFFA78BFA);
  static const Color darkAccentPressed = Color(0xFF8B5CF6);
  static const Color darkSecondary = Color(0xFFFDBA74);
  static const Color darkOnSecondary = Color(0xFF3B1D00);
  static const Color darkTextPrimary = Color(0xFFF8F5FF);
  static const Color darkTextSecondary = Color(0xFFC4B5D9);
  static const Color darkBorder = Color(0xFF33244A);

  // ---- Light mode (white + violet + light orange) ----
  static const Color lightBase = Color(0xFFFFFFFF);
  static const Color lightGlass = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFF6D28D9);
  static const Color lightAccentPressed = Color(0xFF5B21B6);
  static const Color lightSecondary = Color(0xFFFDBA74);
  static const Color lightOnSecondary = Color(0xFF3B1D00);
  static const Color lightTextPrimary = Color(0xFF1C1530);
  static const Color lightTextSecondary = Color(0xFF6B6478);
  static const Color lightBorder = Color(0xFFE9E1F5);

  // ---- Shared states ----
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFF59E0B);

  /// Terminal-style surface used by the agent run timeline.
  static const Color terminalDark = Color(0xFF120A1F);
  static const Color terminalLight = Color(0xFFF7F2FF);
}
