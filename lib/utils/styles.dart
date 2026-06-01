import 'package:flutter/material.dart';

class AppStyles {
  // Cohesive HSL-based Harmonious Dark Color Palette
  static const Color backgroundStart = Color(0xFF0F172A); // Dark Slate Blue
  static const Color backgroundEnd = Color(0xFF020617);   // Almost Black Slate
  
  static const Color glassCardBg = Color(0x1F1E293B);      // Semi-transparent Slate
  static const Color glassCardBorder = Color(0x33475569);  // Subtle Border
  
  static const Color primaryAccent = Color(0xFF38BDF8);    // Bright Celestial Blue
  static const Color secondaryAccent = Color(0xFF818CF8);  // Indigo Accent
  static const Color successColor = Color(0xFF34D399);     // Emerald Green
  static const Color errorColor = Color(0xFFF87171);       // Coral Red
  static const Color warningColor = Color(0xFFFBBF24);     // Amber Warning
  
  static const Color textPrimary = Color(0xFFF8FAFC);      // Ice White
  static const Color textSecondary = Color(0xFF94A3B8);    // Slate Grey
  static const Color textMuted = Color(0xFF64748B);        // Deep Slate Grey

  // Gradients
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [backgroundStart, backgroundEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [primaryAccent, secondaryAccent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Card Decoration (Glassmorphism)
  static BoxDecoration glassDecoration({double radius = 16.0, Color? borderColor}) {
    return BoxDecoration(
      color: glassCardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? glassCardBorder,
        width: 1.5,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 12.0,
          offset: Offset(0, 4),
        )
      ]
    );
  }

  // Text Styles
  static const TextStyle titleHuge = TextStyle(
    color: textPrimary,
    fontSize: 32.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const TextStyle titleLarge = TextStyle(
    color: textPrimary,
    fontSize: 24.0,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
  );

  static const TextStyle bodyLarge = TextStyle(
    color: textPrimary,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyMedium = TextStyle(
    color: textSecondary,
    fontSize: 14.0,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle caption = TextStyle(
    color: textMuted,
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
  );
}
