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

  /// Resolved absolute path to ffmpeg, or `null` if unavailable.
  static String? _ffmpegPath;
  static bool _ffmpegChecked = false;

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

  /// Try ffmpeg first (accurate PCM decode), fall back to byte-level
  /// approximation when ffmpeg is unavailable (e.g. macOS App Sandbox).
  static Future<List<double>> _doExtract(
    String filePath,
    int sampleCount,
  ) async {
    try {
      return await _extractFromFfmpeg(filePath, sampleCount: sampleCount);
    } on WaveformExtractionException catch (e) {
      debugPrint(
        'WaveformExtractor: ffmpeg unavailable ($e), '
        'falling back to byte-level approximation',
      );
      return _extractFromRawBytes(filePath, sampleCount: sampleCount);
    }
  }

  // ---------------------------------------------------------------------------
  // ffmpeg-based extraction (accurate)
  // ---------------------------------------------------------------------------

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

    return waveform;
  }

  /// Find and execute ffmpeg, trying absolute paths first (the sandbox may
  /// not have `/opt/homebrew/bin` on PATH).
  static Future<ProcessResult> _runFfmpeg(String filePath) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
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
      throw WaveformExtractionException(
        'ffmpeg execution failed (${e.message})',
      );
    }
  }

  /// Resolve the absolute path to the ffmpeg binary once, then cache it.
  static Future<String?> _resolveFfmpeg() async {
    if (_ffmpegChecked) return _ffmpegPath;
    _ffmpegChecked = true;

    // Check well-known absolute paths first (Homebrew Apple Silicon / Intel).
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

    // Fall back to PATH-based lookup.
    try {
      final result = Process.runSync('which', ['ffmpeg']);
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty && File(path).existsSync()) {
        _ffmpegPath = path;
        return _ffmpegPath;
      }
    } catch (_) {}

    return null;
  }

  // ---------------------------------------------------------------------------
  // Byte-level fallback (approximate, no external dependencies)
  // ---------------------------------------------------------------------------

  /// Generate a waveform approximation by reading raw file bytes.
  ///
  /// For uncompressed formats (WAV) this reads the actual PCM data chunk.
  /// For compressed formats (MP3, M4A, etc.) it estimates amplitude from
  /// byte-level energy, which gives a visually reasonable shape.
  static Future<List<double>> _extractFromRawBytes(
    String filePath, {
    required int sampleCount,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();
    if (fileSize < 64) {
      return List<double>.filled(sampleCount, 0.0);
    }

    final ext = filePath.split('.').last.toLowerCase();
    if (ext == 'wav') {
      return _extractFromWav(file, fileSize, sampleCount);
    }

    return _extractByteEnergy(file, fileSize, sampleCount);
  }

  /// Parse a WAV file and extract peak amplitude from the PCM data chunk.
  static Future<List<double>> _extractFromWav(
    File file,
    int fileSize,
    int sampleCount,
  ) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      // Read the header (first 44 bytes minimum).
      final header = Uint8List(min(128, fileSize));
      await raf.readInto(header);

      // Verify RIFF/WAVE.
      if (header.length < 44 ||
          header[0] != 0x52 || // R
          header[1] != 0x49 || // I
          header[2] != 0x46 || // F
          header[3] != 0x46 || // F
          header[8] != 0x57 || // W
          header[9] != 0x41 || // A
          header[10] != 0x56 || // V
          header[11] != 0x45) {
        // E
        // Not a valid WAV — fall back to byte-energy.
        return _extractByteEnergy(file, fileSize, sampleCount);
      }

      // Find the "data" chunk.
      var offset = 12;
      int dataOffset = -1;
      int dataSize = -1;
      while (offset + 8 <= header.length) {
        final chunkId = String.fromCharCodes(
          header.sublist(offset, offset + 4),
        );
        final chunkSize =
            header[offset + 4] |
            (header[offset + 5] << 8) |
            (header[offset + 6] << 16) |
            (header[offset + 7] << 24);
        if (chunkId == 'data') {
          dataOffset = offset + 8;
          dataSize = chunkSize;
          break;
        }
        offset += 8 + chunkSize;
      }

      if (dataOffset < 0 || dataSize <= 0) {
        return _extractByteEnergy(file, fileSize, sampleCount);
      }

      // Read bits-per-sample from the fmt chunk (byte 34-35).
      final bitsPerSample = header[34] | (header[35] << 8);
      final bytesPerSample = (bitsPerSample / 8).ceil();
      final numChannels = header[22] | (header[23] << 8);
      final frameSize = bytesPerSample * numChannels;
      if (frameSize <= 0) {
        return _extractByteEnergy(file, fileSize, sampleCount);
      }

      final totalFrames = dataSize ~/ frameSize;
      if (totalFrames <= 0) {
        return List<double>.filled(sampleCount, 0.0);
      }

      // Read PCM data in chunks and compute peaks.
      final waveform = List<double>.filled(sampleCount, 0.0);
      // Read a reasonable amount at a time.
      const maxReadBytes = 1024 * 1024; // 1 MB

      await raf.setPosition(dataOffset);
      final readableSize = min(dataSize, fileSize - dataOffset);
      final bytes = Uint8List(min(readableSize, maxReadBytes));
      final bytesRead = await raf.readInto(bytes);

      final usableFrames = min(totalFrames, bytesRead ~/ frameSize);
      for (var i = 0; i < sampleCount; i++) {
        final startFrame = (i * usableFrames / sampleCount).floor();
        var endFrame = ((i + 1) * usableFrames / sampleCount).floor();
        if (endFrame <= startFrame) endFrame = startFrame + 1;
        if (endFrame > usableFrames) endFrame = usableFrames;

        var peak = 0;
        for (var f = startFrame; f < endFrame; f++) {
          final byteOffset = f * frameSize;
          int sample;
          if (bytesPerSample == 2) {
            final raw =
                (bytes[byteOffset] & 0xff) |
                ((bytes[byteOffset + 1] & 0xff) << 8);
            sample = raw >= 0x8000 ? raw - 0x10000 : raw;
          } else if (bytesPerSample == 1) {
            sample = (bytes[byteOffset] & 0xff) - 128;
          } else {
            sample = bytes[byteOffset] & 0xff;
          }
          final amplitude = sample < 0 ? -sample : sample;
          if (amplitude > peak) peak = amplitude;
        }

        final maxVal = bytesPerSample == 2
            ? 32768.0
            : (bytesPerSample == 1 ? 128.0 : 256.0);
        waveform[i] = peak / maxVal;
      }

      return waveform;
    } finally {
      await raf.close();
    }
  }

  /// Estimate waveform from raw file bytes (works for any format).
  ///
  /// For compressed formats (MP3, M4A, OGG, etc.) raw byte values don't
  /// map to amplitude.  Instead we measure **local byte entropy** — the
  /// number of distinct byte values within each window.  Silent/quiet
  /// sections produce simpler encoded data (fewer unique bytes) while loud
  /// sections produce more complex data (more unique bytes).
  static Future<List<double>> _extractByteEnergy(
    File file,
    int fileSize,
    int sampleCount,
  ) async {
    // Skip headers / metadata (first ~8 KB) to avoid tag-related spikes.
    const headerSkip = 8192;
    final dataStart = min(headerSkip, fileSize ~/ 4);
    final dataLength = fileSize - dataStart;
    if (dataLength < sampleCount) {
      return List<double>.filled(sampleCount, 0.3);
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(dataStart);
      // Cap the read to 8 MB to keep memory reasonable.
      final readSize = min(dataLength, 8 * 1024 * 1024);
      final bytes = Uint8List(readSize);
      final bytesRead = await raf.readInto(bytes);

      final bytesPerBin = bytesRead / sampleCount;
      final rawWaveform = List<double>.filled(sampleCount, 0.0);

      // Reusable histogram to count distinct byte values per bin.
      final histogram = List<int>.filled(256, 0);

      for (var i = 0; i < sampleCount; i++) {
        final start = (i * bytesPerBin).floor();
        var end = ((i + 1) * bytesPerBin).floor();
        if (end <= start) end = start + 1;
        if (end > bytesRead) end = bytesRead;

        // Count distinct byte values in this window.
        for (var j = start; j < end; j++) {
          histogram[bytes[j]]++;
        }
        var uniqueCount = 0;
        for (var k = 0; k < 256; k++) {
          if (histogram[k] > 0) {
            uniqueCount++;
            histogram[k] = 0; // reset for next bin
          }
        }
        rawWaveform[i] = uniqueCount.toDouble();
      }

      // Normalise to 0.0–1.0 range.
      var maxVal = 0.0;
      var minVal = double.infinity;
      for (final v in rawWaveform) {
        if (v > maxVal) maxVal = v;
        if (v < minVal) minVal = v;
      }
      final range = maxVal - minVal;
      if (range <= 0) {
        return List<double>.filled(sampleCount, 0.3);
      }

      // Contrast-stretch to use the full 0–1 range, then apply sqrt to
      // boost quieter regions and give a more natural waveform shape.
      for (var i = 0; i < sampleCount; i++) {
        rawWaveform[i] = sqrt((rawWaveform[i] - minVal) / range);
      }

      // Smooth with a 5-sample moving average for a cleaner look.
      final smoothed = List<double>.filled(sampleCount, 0.0);
      for (var i = 0; i < sampleCount; i++) {
        var sum = 0.0;
        var count = 0;
        for (var k = i - 2; k <= i + 2; k++) {
          if (k >= 0 && k < sampleCount) {
            sum += rawWaveform[k];
            count++;
          }
        }
        smoothed[i] = (sum / count).clamp(0.05, 1.0);
      }

      return smoothed;
    } finally {
      await raf.close();
    }
  }
}
