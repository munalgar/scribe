import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies audio files into the app's Application Support directory so they
/// remain accessible across app restarts under the macOS App Sandbox.
class AudioCacheService {
  static Directory? _cacheDir;

  /// Returns the audio cache directory, creating it if needed.
  static Future<Directory> getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, 'audio_cache'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Copy [originalPath] into the audio cache.
  ///
  /// Returns the cached file's absolute path, or `null` if the copy fails.
  static Future<String?> cacheFile(String originalPath) async {
    try {
      final cacheDir = await getCacheDir();
      final fileName = p.basename(originalPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final destPath = p.join(cacheDir.path, '${timestamp}_$fileName');

      await File(originalPath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('AudioCacheService: failed to cache $originalPath — $e');
      return null;
    }
  }

  /// Best-effort deletion of a previously cached file.
  static Future<void> deleteCachedFile(String cachedPath) async {
    try {
      final file = File(cachedPath);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort — ignore errors.
    }
  }
}
