import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:finaudio/services/settings_service.dart';

/// Renders a responsive wallpaper backdrop behind app content with
/// hardware-accelerated adjustments for brightness, contrast, blur, and vignette.
class AppWallpaperBackdrop extends StatelessWidget {
  final SettingsService settingsService;
  final Widget child;

  const AppWallpaperBackdrop({
    super.key,
    required this.settingsService,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final wallpaperPath = settingsService.wallpaperPath;
    final hasWallpaper = settingsService.hasWallpaper &&
        wallpaperPath != null &&
        File(wallpaperPath).existsSync();

    if (!hasWallpaper) {
      return Container(
        color: settingsService.backgroundColor,
        child: child,
      );
    }

    final brightness = settingsService.wallpaperBrightness;
    final contrast = settingsService.wallpaperContrast;
    final vignette = settingsService.wallpaperVignette;
    final blur = settingsService.wallpaperBlur;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Wallpaper Image with Brightness + Contrast + Blur
        Positioned.fill(
          child: RepaintBoundary(
            child: _buildFilteredWallpaper(
              path: wallpaperPath,
              brightness: brightness,
              contrast: contrast,
              blur: blur,
            ),
          ),
        ),

        // 2. Vignette radial gradient overlay
        if (vignette > 0.01)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: (vignette * 0.92).clamp(0.0, 0.98)),
                    ],
                    stops: const [0.30, 1.0],
                  ),
                ),
              ),
            ),
          ),

        // 3. Subtle background color overlay to unify theme tint
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: settingsService.backgroundColor.withValues(alpha: 0.32),
            ),
          ),
        ),

        // 4. Foreground Content
        child,
      ],
    );
  }

  Widget _buildFilteredWallpaper({
    required String path,
    required double brightness,
    required double contrast,
    required double blur,
  }) {
    Widget imageWidget = Image.file(
      File(path),
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );

    // Apply Brightness & Contrast 4x5 ColorMatrix
    final matrixFilter = _buildColorMatrixFilter(brightness, contrast);
    if (matrixFilter != null) {
      imageWidget = ColorFiltered(
        colorFilter: matrixFilter,
        child: imageWidget,
      );
    }

    // Apply Blur filter if requested
    if (blur > 0.1) {
      imageWidget = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  /// Calculates a 4x5 GPU color matrix applying brightness (-1.0..1.0) and contrast (0.5..2.0).
  static ColorFilter? _buildColorMatrixFilter(double brightness, double contrast) {
    if ((brightness.abs() < 0.001) && (contrast - 1.0).abs() < 0.001) {
      return null;
    }
    // R' = contrast * R + offset
    // G' = contrast * G + offset
    // B' = contrast * B + offset
    // offset = 128 * (1 - contrast) + brightness * 255
    final offset = 128.0 * (1.0 - contrast) + (brightness * 255.0);
    final matrix = <double>[
      contrast, 0, 0, 0, offset,
      0, contrast, 0, 0, offset,
      0, 0, contrast, 0, offset,
      0, 0, 0, 1, 0,
    ];
    return ColorFilter.matrix(matrix);
  }
}
