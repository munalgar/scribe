import 'dart:io';

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

    final extraction = _extractFromFfmpeg(
      filePath,
      sampleCount: requestedSamples,
    ).then((waveform) {
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

  static Future<ProcessResult> _runFfmpeg(String filePath) async {
    try {
      return await Process.run(
        'ffmpeg',
        [
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
        ],
        stdoutEncoding: null,
      );
    } on ProcessException catch (e) {
      throw WaveformExtractionException(
        'ffmpeg is required to generate waveforms (${e.message})',
      );
    }
  }
}
