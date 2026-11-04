import 'package:flutter/material.dart';

class AppTheme {
  static const Color seed = Color(0xFF2563EB);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final isDark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1116) : const Color(0xFFF5F7FB),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? const Color(0xFF232A34) : const Color(0xFFE6EAF2),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B222C) : const Color(0xFFF0F3F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        linearMinHeight: 6,
      ),
    );
  }
}

/// Colour + icon per file category.
class FileKind {
  final IconData icon;
  final Color color;
  const FileKind(this.icon, this.color);

  static FileKind of(String name) {
    final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (const ['mp4', 'mkv', 'webm', 'avi', 'mov', '3gp'].contains(e)) {
      return const FileKind(Icons.play_circle_outline, Color(0xFFEF4444));
    }
    if (const ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'].contains(e)) {
      return const FileKind(Icons.music_note_rounded, Color(0xFF8B5CF6));
    }
    if (const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(e)) {
      return const FileKind(Icons.image_outlined, Color(0xFF10B981));
    }
    if (const ['zip', 'rar', '7z', 'tar', 'gz', 'iso'].contains(e)) {
      return const FileKind(Icons.folder_zip_outlined, Color(0xFFF59E0B));
    }
    if (e == 'apk') {
      return const FileKind(Icons.android_rounded, Color(0xFF22C55E));
    }
    if (e == 'pdf') {
      return const FileKind(Icons.picture_as_pdf_outlined, Color(0xFFDC2626));
    }
    return const FileKind(Icons.insert_drive_file_outlined, Color(0xFF64748B));
  }
}
