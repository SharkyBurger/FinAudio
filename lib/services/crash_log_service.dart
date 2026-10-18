import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogService {
  static final CrashLogService instance = CrashLogService._internal();
  CrashLogService._internal();

  bool _initialized = false;
  final List<String> _inMemoryLogs = [];

  static const String folderName = 'FinAudioCrashLogs';
  static const String logFileName = 'crash.log';

  /// Initialize global uncaught exception handlers.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      logCrash(
        details.exception,
        details.stack,
        reason: 'FlutterError.onError',
        context: details.context?.toString(),
      );
      if (originalOnError != null) {
        originalOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      logCrash(error, stack, reason: 'PlatformDispatcher.instance.onError');
      return false; // let default handling continue
    };

    // Ensure the folder exists on startup
    await ensureDirectoryExists();
  }

  /// Get candidate directory paths for the FinAudioCrashLogs folder.
  Future<List<Directory>> getTargetDirectories() async {
    final dirs = <Directory>[];

    if (!kIsWeb && Platform.isAndroid) {
      // 1. Primary phone user-accessible Documents folder
      for (final root in ['/storage/emulated/0/Documents', '/sdcard/Documents']) {
        try {
          final dir = Directory('$root/$folderName');
          dirs.add(dir);
        } catch (_) {}
      }

      // 2. App-specific external storage Documents folder
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          dirs.add(Directory('${extDir.path}/Documents/$folderName'));
          dirs.add(Directory('${extDir.path}/$folderName'));
        }
      } catch (_) {}
    } else if (!kIsWeb && Platform.isWindows) {
      try {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          dirs.add(Directory('$userProfile\\Documents\\$folderName'));
        }
      } catch (_) {}
    }

    // 3. Fallback to application documents directory
    try {
      final appDocs = await getApplicationDocumentsDirectory();
      dirs.add(Directory('${appDocs.path}/$folderName'));
    } catch (_) {}

    return dirs;
  }

  /// Ensure the target directories exist.
  Future<void> ensureDirectoryExists() async {
    final targets = await getTargetDirectories();
    for (final dir in targets) {
      try {
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// Log a crash or error to the FinAudioCrashLogs folder and in memory.
  Future<void> logCrash(
    Object error,
    StackTrace? stack, {
    String? reason,
    String? context,
  }) async {
    final now = DateTime.now().toIso8601String();
    final os = !kIsWeb ? '${Platform.operatingSystem} ${Platform.operatingSystemVersion}' : 'Web';

    final buffer = StringBuffer();
    buffer.writeln('================================================================================');
    buffer.writeln('FINAUDIO CRASH LOG');
    buffer.writeln('Timestamp: $now');
    buffer.writeln('Platform: $os');
    if (reason != null && reason.isNotEmpty) {
      buffer.writeln('Reason: $reason');
    }
    if (context != null && context.isNotEmpty) {
      buffer.writeln('Context: $context');
    }
    buffer.writeln('Error: $error');
    if (stack != null) {
      buffer.writeln('\nStack Trace:');
      buffer.writeln(stack.toString().trim());
    }
    buffer.writeln('================================================================================\n');

    final entry = buffer.toString();
    _inMemoryLogs.add(entry);
    if (_inMemoryLogs.length > 50) {
      _inMemoryLogs.removeAt(0);
    }

    final targets = await getTargetDirectories();
    for (final dir in targets) {
      try {
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        final file = File('${dir.path}/$logFileName');
        file.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      } catch (_) {
        // Continue to other candidate dirs
      }
    }
  }

  /// Read the full combined crash log text.
  Future<String> readLogs() async {
    final targets = await getTargetDirectories();
    for (final dir in targets) {
      try {
        final file = File('${dir.path}/$logFileName');
        if (file.existsSync()) {
          final content = file.readAsStringSync().trim();
          if (content.isNotEmpty) {
            return content;
          }
        }
      } catch (_) {}
    }

    if (_inMemoryLogs.isNotEmpty) {
      return _inMemoryLogs.join('\n');
    }

    return 'No crashes recorded. The app is running normally!';
  }

  /// Get the primary file path where the crash log is stored.
  Future<String> getPrimaryLogPath() async {
    final targets = await getTargetDirectories();
    for (final dir in targets) {
      try {
        if (dir.existsSync()) {
          return '${dir.path}/$logFileName';
        }
      } catch (_) {}
    }
    if (targets.isNotEmpty) {
      return '${targets.first.path}/$logFileName';
    }
    return 'Documents/$folderName/$logFileName';
  }

  /// Clear all crash logs.
  Future<void> clearLogs() async {
    _inMemoryLogs.clear();
    final targets = await getTargetDirectories();
    for (final dir in targets) {
      try {
        final file = File('${dir.path}/$logFileName');
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }

  /// Copy all crash logs to the user's system clipboard.
  Future<bool> copyToClipboard() async {
    try {
      final logs = await readLogs();
      await Clipboard.setData(ClipboardData(text: logs));
      return true;
    } catch (_) {
      return false;
    }
  }
}

