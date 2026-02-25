import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class WaveformExtractionException implements Exception {
  final String message;

  const WaveformExtractionException(this.message);

  @override
  String toString() => 'WaveformExtractionException: $message';
}

class WaveformExtractor {
  static const int defaultSampleCount = 320;
  static const int _decodeSampleRate = 4000;
  static const int _maxCachedWaveforms = 32;

  static final Map<String, List<double>> _cache = {};
  static final List<String> _cacheOrder = [];
  static final Map<String, Future<List<double>>> _inFlight = {};

  static String? _ffmpegPath;
  static bool _ffmpegPathChecked = false;
  static bool _ffmpegUnavailable = false;
  static bool _ffmpegUnavailableLogged = false;
  static String? _ffmpegUnavailableReason;

  static Future<List<double>> extract(
    String filePath, {
    int sampleCount = defaultSampleCount,
  }) async {
    final requestedSamples = sampleCount.clamp(16, 4096).toInt();
    final file = File(filePath);
    if (!await file.exists()) {
      return List<double>.filled(requestedSamples, 0.0);
    }

    final stat = await file.stat();
    final cacheKey =
        '$filePath::$requestedSamples::${stat.size}::${stat.modified.millisecondsSinceEpoch}';

    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final extraction = _doExtract(filePath, requestedSamples).then((waveform) {
      _cache[cacheKey] = waveform;
      _cacheOrder
        ..remove(cacheKey)
        ..add(cacheKey);
      while (_cacheOrder.length > _maxCachedWaveforms) {
        final oldest = _cacheOrder.removeAt(0);
        _cache.remove(oldest);
      }
      return waveform;
    });

    _inFlight[cacheKey] = extraction;
    try {
      return await extraction;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  static Future<List<double>> _doExtract(
    String filePath,
    int sampleCount,
  ) async {
    if (_ffmpegUnavailable) {
      _logFfmpegUnavailableOnce(
        _ffmpegUnavailableReason ?? 'ffmpeg unavailable',
      );
      return _extractFromRawBytes(filePath, sampleCount: sampleCount);
    }

    try {
      return await _extractFromFfmpeg(filePath, sampleCount: sampleCount);
    } on WaveformExtractionException catch (e) {
      _logFfmpegUnavailableOnce(e.message);
      return _extractFromRawBytes(filePath, sampleCount: sampleCount);
    }
  }

  static Future<List<double>> _extractFromFfmpeg(
    String filePath, {
    required int sampleCount,
  }) async {
    final result = await _runFfmpeg(filePath);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?)?.trim();
      throw WaveformExtractionException(
        stderr?.isNotEmpty == true
            ? stderr!
            : 'ffmpeg failed with exit code ${result.exitCode}',
      );
    }

    final stdout = result.stdout;
    if (stdout is! List<int> || stdout.length < 2) {
      return List<double>.filled(sampleCount, 0.0);
    }

    final samples = stdout.length ~/ 2;
    if (samples <= 0) {
      return List<double>.filled(sampleCount, 0.0);
    }

    final waveform = List<double>.filled(sampleCount, 0.0);
    for (var i = 0; i < sampleCount; i++) {
      final start = (i * samples / sampleCount).floor();
      var end = ((i + 1) * samples / sampleCount).floor();
      if (end <= start) {
        end = start + 1;
      }
      if (end > samples) {
        end = samples;
      }

      var peak = 0;
      for (var sample = start; sample < end; sample++) {
        final sampleOffset = sample * 2;
        final raw =
            (stdout[sampleOffset] & 0xff) |
            ((stdout[sampleOffset + 1] & 0xff) << 8);
        final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
        final amplitude = signed < 0 ? -signed : signed;
        if (amplitude > peak) {
          peak = amplitude;
        }
      }

      waveform[i] = peak / 32768.0;
    }

    return _normalizeWaveform(waveform);
  }

  static Future<ProcessResult> _runFfmpeg(String filePath) async {
    if (_ffmpegUnavailable) {
      throw WaveformExtractionException(
        _ffmpegUnavailableReason ?? 'ffmpeg unavailable',
      );
    }

    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
      _markFfmpegUnavailable('ffmpeg not found');
      throw const WaveformExtractionException('ffmpeg not found');
    }

    try {
      return await Process.run(ffmpeg, [
        '-v',
        'error',
        '-i',
        filePath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '$_decodeSampleRate',
        '-f',
        's16le',
        '-acodec',
        'pcm_s16le',
        '-',
      ], stdoutEncoding: null);
    } on ProcessException catch (e) {
      final message = e.message.trim();
      _markFfmpegUnavailable('ffmpeg execution failed ($message)');
      throw WaveformExtractionException('ffmpeg execution failed ($message)');
    }
  }

  static Future<String?> _resolveFfmpeg() async {
    if (_ffmpegPathChecked) {
      return _ffmpegPath;
    }
    _ffmpegPathChecked = true;

    const candidates = [
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/usr/bin/ffmpeg',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        _ffmpegPath = path;
        return _ffmpegPath;
      }
    }

    try {
      final which = Process.runSync('which', ['ffmpeg']);
      final path = (which.stdout as String?)?.trim() ?? '';
      if (path.isNotEmpty && File(path).existsSync()) {
        _ffmpegPath = path;
        return _ffmpegPath;
      }
    } catch (_) {}

    return null;
  }

  static void _markFfmpegUnavailable(String reason) {
    _ffmpegUnavailable = true;
    _ffmpegUnavailableReason = reason;
  }

  static void _logFfmpegUnavailableOnce(String reason) {
    if (_ffmpegUnavailableLogged) return;
    _ffmpegUnavailableLogged = true;
    debugPrint(
      'WaveformExtractor: ffmpeg unavailable ($reason), '
      'falling back to byte-level approximation',
    );
  }

  static Future<List<double>> _extractFromRawBytes(
    String filePath, {
    required int sampleCount,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();
    if (fileSize < 64) {
      return List<double>.filled(sampleCount, 0.0);
    }

    final dataStart = min(8192, fileSize ~/ 4);
    final dataLength = fileSize - dataStart;
    if (dataLength <= 0) {
      return List<double>.filled(sampleCount, 0.2);
    }

    final readSize = min(dataLength, 8 * 1024 * 1024);
    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(dataStart);
      final bytes = Uint8List(readSize);
      final bytesRead = await raf.readInto(bytes);
      if (bytesRead <= 0) {
        return List<double>.filled(sampleCount, 0.2);
      }

      final values = List<double>.filled(sampleCount, 0.0);
      final bytesPerBin = bytesRead / sampleCount;
      for (var i = 0; i < sampleCount; i++) {
        final start = (i * bytesPerBin).floor();
        var end = ((i + 1) * bytesPerBin).floor();
        if (end <= start) end = start + 1;
        if (end > bytesRead) end = bytesRead;

        var energy = 0.0;
        for (var j = start; j < end; j++) {
          energy += (bytes[j] - 128).abs() / 128.0;
        }
        values[i] = energy / max(1, end - start);
      }

      return _normalizeWaveform(values);
    } finally {
      await raf.close();
    }
  }

  static List<double> _normalizeWaveform(List<double> values) {
    if (values.isEmpty) return values;

    final sorted = [...values]..sort();
    final floor = _percentile(sorted, 0.1);
    final ceiling = max(_percentile(sorted, 0.95), floor + 1e-6);
    final range = ceiling - floor;

    final normalized = List<double>.filled(values.length, 0.0);
    for (var i = 0; i < values.length; i++) {
      final unit = ((values[i] - floor) / range).clamp(0.0, 1.0).toDouble();
      normalized[i] = pow(unit, 0.7).toDouble().clamp(0.04, 1.0);
    }

    if (normalized.length < 3) return normalized;

    final smoothed = List<double>.filled(normalized.length, 0.0);
    for (var i = 0; i < normalized.length; i++) {
      final left = normalized[max(0, i - 1)];
      final center = normalized[i];
      final right = normalized[min(normalized.length - 1, i + 1)];
      smoothed[i] = (left * 0.2 + center * 0.6 + right * 0.2).clamp(0.04, 1.0);
    }
    return smoothed;
  }

  static double _percentile(List<double> sortedValues, double q) {
    if (sortedValues.isEmpty) return 0.0;
    final clampedQ = q.clamp(0.0, 1.0).toDouble();
    final position = (sortedValues.length - 1) * clampedQ;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) {
      return sortedValues[lower];
    }
    final weight = position - lower;
    return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
  }
}
