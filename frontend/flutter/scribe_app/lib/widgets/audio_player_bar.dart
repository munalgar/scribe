import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../services/waveform_extractor.dart';
import '../theme.dart';

class AudioPlayerBar extends StatefulWidget {
  final Player player;
  final String? filePath;
  final Duration? durationHint;
  final bool enabled;

  const AudioPlayerBar({
    super.key,
    required this.player,
    this.filePath,
    this.durationHint,
    this.enabled = true,
  });

  @override
  State<AudioPlayerBar> createState() => AudioPlayerBarState();
}

class AudioPlayerBarState extends State<AudioPlayerBar> {
  static const int _coarseSeekSeconds = 5;
  static const int _fineSeekSeconds = 1;
  static const Duration _liveSeekInterval = Duration(milliseconds: 45);
  static const int _waveformSampleCount = 320;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _isSeeking = false;
  bool _fineSeekEnabled = false;
  double _seekFraction = 0;
  String? _loadedPath;
  String? _sourceError;
  bool _awaitingResolvedDuration = false;
  bool _hasFinalDuration = false;
  int _sourceLoadVersion = 0;
  Timer? _durationSettleTimer;
  Timer? _liveSeekTimer;
  Duration? _pendingLiveSeekTarget;
  bool _liveSeekInFlight = false;
  final Map<String, Duration> _durationCache = {};
  List<double>? _waveformSamples;
  bool _waveformLoading = false;
  int _waveformLoadVersion = 0;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _applySeedDuration();
    _awaitingResolvedDuration = widget.filePath != null && !_hasFinalDuration;
    _setupListeners();
    _requestWaveformLoad();
    _preloadSource();
  }

  @override
  void dispose() {
    _durationSettleTimer?.cancel();
    _liveSeekTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(AudioPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath) {
      _resetForNewFile();
    } else if (widget.enabled != oldWidget.enabled &&
        widget.enabled &&
        widget.filePath != null) {
      _resetForNewFile();
    }
  }

  void _resetForNewFile() {
    _durationSettleTimer?.cancel();
    _sourceLoadVersion++;
    _waveformLoadVersion++;
    _loadedPath = null;
    _sourceError = null;
    _playing = false;
    _isSeeking = false;
    _position = Duration.zero;
    _hasFinalDuration = false;
    _waveformSamples = null;
    _waveformLoading = false;

    _applySeedDuration();

    if (widget.filePath == null) {
      _awaitingResolvedDuration = false;
      widget.player.stop();
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
      });
      return;
    }

    // Ignore stale stream events while switching sources.
    _awaitingResolvedDuration = !_hasFinalDuration;
    widget.player.stop();
    if (mounted) {
      setState(() {});
    }
    _requestWaveformLoad();
    _preloadSource(_sourceLoadVersion);
  }

  void _requestWaveformLoad() {
    final selectedPath = widget.filePath;
    final requestVersion = ++_waveformLoadVersion;
    final shouldLoad = widget.enabled && selectedPath != null;
    _waveformSamples = null;
    _waveformLoading = shouldLoad;
    if (!shouldLoad) return;
    _loadWaveform(selectedPath, requestVersion);
  }

  Future<void> _loadWaveform(String filePath, int requestVersion) async {
    try {
      final samples = await WaveformExtractor.extract(
        filePath,
        sampleCount: _waveformSampleCount,
      );
      if (!mounted ||
          requestVersion != _waveformLoadVersion ||
          widget.filePath != filePath) {
        return;
      }
      setState(() {
        _waveformSamples = samples;
        _waveformLoading = false;
      });
    } on Exception catch (e) {
      if (!mounted ||
          requestVersion != _waveformLoadVersion ||
          widget.filePath != filePath) {
        return;
      }
      debugPrint('AudioPlayerBar waveform extraction: $e');
      setState(() {
        _waveformLoading = false;
        _waveformSamples = null;
      });
    }
  }

  void _applySeedDuration() {
    final path = widget.filePath;
    if (path == null) return;

    final seededDuration = _durationCache[path] ?? widget.durationHint;
    if (seededDuration == null || seededDuration <= Duration.zero) return;

    _duration = seededDuration;
    _hasFinalDuration = true;
    _durationCache[path] = seededDuration;
  }

  Future<void> _preloadSource([int? loadVersion]) async {
    final expectedVersion = loadVersion ?? _sourceLoadVersion;
    final selectedPath = widget.filePath;
    if (!widget.enabled || selectedPath == null) {
      if (_sourceLoadVersion == expectedVersion) {
        _awaitingResolvedDuration = false;
      }
      return;
    }
    final requestedPath = selectedPath;

    // Early check: surface a clear message when the file is missing or
    // inaccessible (e.g. sandbox revoked access after restart).
    if (!File(requestedPath).existsSync()) {
      if (mounted && _sourceLoadVersion == expectedVersion) {
        setState(() => _sourceError = 'Audio file not accessible');
        _awaitingResolvedDuration = false;
      }
      return;
    }

    try {
      await widget.player.open(
        Media('file:///${requestedPath.replaceAll('\\', '/')}'),
        play: false,
      );
      if (widget.filePath == requestedPath &&
          _sourceLoadVersion == expectedVersion) {
        _loadedPath = requestedPath;
        if (!_hasFinalDuration) {
          _queueDurationResolution();
        }
        if (mounted) setState(() {});
      }
    } on Exception catch (e) {
      if (mounted && _sourceLoadVersion == expectedVersion) {
        setState(() => _sourceError = 'Failed to load audio');
        debugPrint('AudioPlayerBar preload: $e');
      }
    } finally {
      if (_sourceLoadVersion == expectedVersion) {
        if (_sourceError != null || widget.filePath == null) {
          _awaitingResolvedDuration = false;
        }
      }
    }
  }

  void _queueDurationResolution() {
    if (_hasFinalDuration) return;
    _durationSettleTimer?.cancel();
    final expectedVersion = _sourceLoadVersion;
    _durationSettleTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || expectedVersion != _sourceLoadVersion) return;
      if (widget.filePath == null || _loadedPath != widget.filePath) return;
      if (!_isSelectedMediaActive()) return;
      final settledDuration = widget.player.state.duration;
      if (settledDuration == Duration.zero) {
        // Metadata can arrive slightly later; keep waiting.
        _queueDurationResolution();
        return;
      }
      if (_duration == settledDuration && _hasFinalDuration) return;
      setState(() {
        _awaitingResolvedDuration = false;
        _hasFinalDuration = true;
        _duration = settledDuration;
        final path = widget.filePath;
        if (path != null) {
          _durationCache[path] = settledDuration;
        }
        if (_position > settledDuration) {
          _position = settledDuration;
        }
      });
    });
  }

  String? _selectedMediaUri() {
    final path = widget.filePath;
    if (path == null) return null;
    return Media.normalizeURI('file:///${path.replaceAll('\\', '/')}');
  }

  String? _activeMediaUri() {
    final playlist = widget.player.state.playlist;
    if (playlist.medias.isEmpty) return null;
    final index = playlist.index;
    if (index < 0 || index >= playlist.medias.length) return null;
    return playlist.medias[index].uri;
  }

  bool _isSelectedMediaActive() {
    final selectedUri = _selectedMediaUri();
    final activeUri = _activeMediaUri();
    if (selectedUri == null) return activeUri == null;
    return selectedUri == activeUri;
  }

  void _setupListeners() {
    _subs.add(
      widget.player.stream.position.listen((p) {
        final selectedPath = widget.filePath;
        if (!mounted || _isSeeking || selectedPath == null) return;
        if (_loadedPath != selectedPath) return;
        if (!_isSelectedMediaActive() || !_hasFinalDuration) return;
        if (_position == p) return;
        setState(() => _position = p);
      }),
    );
    _subs.add(
      widget.player.stream.duration.listen((d) {
        final selectedPath = widget.filePath;
        if (!mounted || !_awaitingResolvedDuration || selectedPath == null) {
          return;
        }
        if (_loadedPath != selectedPath) return;
        if (!_isSelectedMediaActive() || d == Duration.zero) return;
        _queueDurationResolution();
      }),
    );
    _subs.add(
      widget.player.stream.playing.listen((p) {
        if (!mounted || _playing == p) return;
        setState(() => _playing = p);
      }),
    );
    _subs.add(
      widget.player.stream.error.listen((e) {
        if (mounted && e.isNotEmpty) {
          setState(() => _sourceError = 'Playback error');
          debugPrint('media_kit error: $e');
        }
      }),
    );
  }

  bool get isPlaying => _playing;

  Duration get position => _position;

  int get _seekStepSeconds =>
      _fineSeekEnabled ? _fineSeekSeconds : _coarseSeekSeconds;

  Duration get _effectiveDuration {
    final hinted = widget.durationHint;
    if (hinted != null && hinted > Duration.zero) return hinted;
    return _duration;
  }

  bool get hasError => _sourceError != null;

  Future<bool> _ensureSelectedSourceLoaded() async {
    final selectedPath = widget.filePath;
    if (selectedPath == null) return false;
    if (_loadedPath == selectedPath) return true;
    await widget.player.open(
      Media('file:///${selectedPath.replaceAll('\\', '/')}'),
      play: false,
    );
    _loadedPath = selectedPath;
    return true;
  }

  Future<void> togglePlayPause() async {
    if (!widget.enabled || widget.filePath == null) return;
    if (_sourceError != null) return;

    try {
      final ready = await _ensureSelectedSourceLoaded();
      if (!ready) return;
      await widget.player.playOrPause();
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _sourceError = 'Failed to load audio');
        debugPrint('AudioPlayerBar: $e');
      }
    }
  }

  Future<void> seekRelative(int seconds) async {
    final effectiveDuration = _effectiveDuration;
    if (!widget.enabled ||
        effectiveDuration == Duration.zero ||
        _sourceError != null) {
      return;
    }
    final target = _position + Duration(seconds: seconds);
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(
        0,
        effectiveDuration.inMilliseconds,
      ),
    );
    await widget.player.seek(clamped);
  }

  Future<void> seekBackwardByStep() async {
    await seekRelative(-_seekStepSeconds);
  }

  Future<void> seekForwardByStep() async {
    await seekRelative(_seekStepSeconds);
  }

  Future<void> seekTo(Duration position) async {
    if (!widget.enabled || _sourceError != null) return;
    try {
      final ready = await _ensureSelectedSourceLoaded();
      if (!ready) return;
    } on Exception catch (_) {
      return;
    }
    await widget.player.seek(position);
  }

  Duration _durationFromFraction(double fraction) {
    final durationForSeek = _effectiveDuration;
    if (durationForSeek == Duration.zero) return Duration.zero;
    final clampedFraction = fraction.clamp(0.0, 1.0);
    return Duration(
      milliseconds: (clampedFraction * durationForSeek.inMilliseconds).round(),
    );
  }

  void _scheduleLiveSeek(Duration target) {
    _pendingLiveSeekTarget = target;
    if (_liveSeekTimer != null || _liveSeekInFlight) return;
    _liveSeekTimer = Timer(_liveSeekInterval, _flushLiveSeek);
  }

  Future<void> _flushLiveSeek() async {
    _liveSeekTimer = null;
    if (!mounted || !_isSeeking || _liveSeekInFlight) return;
    final target = _pendingLiveSeekTarget;
    if (target == null) return;

    _pendingLiveSeekTarget = null;
    _liveSeekInFlight = true;
    try {
      await seekTo(target);
    } finally {
      _liveSeekInFlight = false;
      if (_isSeeking && _pendingLiveSeekTarget != null) {
        _liveSeekTimer = Timer(_liveSeekInterval, _flushLiveSeek);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAudio = widget.filePath != null && widget.enabled;
    final canPlay = hasAudio && _sourceError == null;
    final effectiveDuration = _effectiveDuration;
    final seekStepLabel =
        '$_seekStepSeconds second${_seekStepSeconds == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          _buildSkipButton(
            icon: Icons.fast_rewind_rounded,
            onPressed: canPlay ? () => seekBackwardByStep() : null,
            tooltip: 'Back $seekStepLabel',
            theme: theme,
          ),
          const SizedBox(width: 4),
          _buildPlayButton(canPlay, theme),
          const SizedBox(width: 4),
          _buildSkipButton(
            icon: Icons.fast_forward_rounded,
            onPressed: canPlay ? () => seekForwardByStep() : null,
            tooltip: 'Forward $seekStepLabel',
            theme: theme,
          ),
          const SizedBox(width: 8),
          _buildFineSeekToggle(theme, canPlay),
          const SizedBox(width: 12),
          if (_sourceError != null) ...[
            Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
            Text(
              _sourceError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ] else ...[
            Text(
              _formatDuration(_position),
              style: ScribeTheme.monoStyle(
                context,
                fontSize: 12,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '/',
              style: ScribeTheme.monoStyle(
                context,
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _formatDuration(effectiveDuration),
              style: ScribeTheme.monoStyle(
                context,
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 20),
          Expanded(
            child: _WaveformScrubber(
              fraction: _isSeeking
                  ? _seekFraction
                  : (effectiveDuration.inMilliseconds > 0
                        ? _position.inMilliseconds /
                              effectiveDuration.inMilliseconds
                        : 0.0),
              enabled: canPlay,
              fineScrub: _fineSeekEnabled,
              theme: theme,
              waveform: _waveformSamples,
              waveformLoading: _waveformLoading,
              onSeekStart: (f) {
                final target = _durationFromFraction(f);
                setState(() {
                  _isSeeking = true;
                  _seekFraction = f;
                  _position = target;
                });
                _scheduleLiveSeek(target);
              },
              onSeekUpdate: (f) {
                final target = _durationFromFraction(f);
                setState(() {
                  _seekFraction = f;
                  _position = target;
                });
                _scheduleLiveSeek(target);
              },
              onSeekEnd: (f) async {
                final target = _durationFromFraction(f);
                _liveSeekTimer?.cancel();
                _liveSeekTimer = null;
                _pendingLiveSeekTarget = null;
                setState(() {
                  _isSeeking = false;
                  _position = target;
                });
                await seekTo(target);
              },
              onSeekCancel: () {
                _liveSeekTimer?.cancel();
                _liveSeekTimer = null;
                _pendingLiveSeekTarget = null;
                if (!_isSeeking) return;
                setState(() {
                  _isSeeking = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(bool enabled, ThemeData theme) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: enabled ? togglePlayPause : null,
        icon: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 26,
        ),
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh,
          foregroundColor: enabled
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSkipButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required ThemeData theme,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          foregroundColor: onPressed != null
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildFineSeekToggle(ThemeData theme, bool enabled) {
    return Tooltip(
      message: _fineSeekEnabled
          ? 'Fine mode on: 1-second skip and precision drag'
          : 'Fine mode off: 5-second skip and normal drag',
      child: SizedBox(
        height: 30,
        child: OutlinedButton.icon(
          onPressed: enabled
              ? () {
                  setState(() {
                    _fineSeekEnabled = !_fineSeekEnabled;
                  });
                }
              : null,
          icon: Icon(
            Icons.tune_rounded,
            size: 14,
            color: _fineSeekEnabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          label: Text(
            'Fine',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _fineSeekEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
            side: BorderSide(
              color: _fineSeekEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            backgroundColor: _fineSeekEnabled
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                : theme.colorScheme.surfaceContainerLow,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _WaveformScrubber extends StatefulWidget {
  final double fraction;
  final bool enabled;
  final bool fineScrub;
  final ThemeData theme;
  final List<double>? waveform;
  final bool waveformLoading;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onSeekCancel;

  const _WaveformScrubber({
    required this.fraction,
    required this.enabled,
    required this.fineScrub,
    required this.theme,
    required this.waveform,
    required this.waveformLoading,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onSeekCancel,
  });

  @override
  State<_WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<_WaveformScrubber> {
  static const double _fineDragScale = 0.2;

  double? _dragFraction;
  double? _dragStartFraction;
  double? _dragStartDx;

  double _fractionFromPosition(Offset local, double width) {
    final safeWidth = width <= 0 ? 1.0 : width;
    return (local.dx / safeWidth).clamp(0.0, 1.0);
  }

  double _fractionFromDrag(DragUpdateDetails details, double width) {
    if (!widget.fineScrub ||
        _dragStartFraction == null ||
        _dragStartDx == null) {
      return _fractionFromPosition(details.localPosition, width);
    }
    final safeWidth = width <= 0 ? 1.0 : width;
    final delta = (details.localPosition.dx - _dragStartDx!) / safeWidth;
    return (_dragStartFraction! + delta * _fineDragScale).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.enabled
              ? (d) {
                  final pointerFraction = _fractionFromPosition(
                    d.localPosition,
                    width,
                  );
                  final f = widget.fineScrub ? widget.fraction : pointerFraction;
                  _dragStartFraction = f;
                  _dragStartDx = d.localPosition.dx;
                  _dragFraction = f;
                  widget.onSeekStart(f);
                }
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (d) {
                  final f = _fractionFromDrag(d, width);
                  _dragFraction = f;
                  widget.onSeekUpdate(f);
                }
              : null,
          onHorizontalDragEnd: widget.enabled
              ? (_) {
                  final f = _dragFraction ?? widget.fraction;
                  _dragFraction = null;
                  _dragStartFraction = null;
                  _dragStartDx = null;
                  widget.onSeekEnd(f);
                }
              : null,
          onHorizontalDragCancel: widget.enabled
              ? () {
                  _dragFraction = null;
                  _dragStartFraction = null;
                  _dragStartDx = null;
                  widget.onSeekCancel();
                }
              : null,
          onTapUp: widget.enabled
              ? (d) {
                  final f = _fractionFromPosition(d.localPosition, width);
                  widget.onSeekEnd(f);
                }
              : null,
          child: SizedBox(
            height: 36,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaveformPainter(
                fraction: widget.fraction,
                playedColor: widget.enabled
                    ? widget.theme.colorScheme.primary
                    : widget.theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.2,
                      ),
                unplayedColor: widget.theme.colorScheme.surfaceContainerHigh,
                cursorColor: widget.theme.colorScheme.primary,
                waveform: widget.waveform,
                waveformLoading: widget.waveformLoading,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double fraction;
  final Color playedColor;
  final Color unplayedColor;
  final Color cursorColor;
  final List<double>? waveform;
  final bool waveformLoading;

  _WaveformPainter({
    required this.fraction,
    required this.playedColor,
    required this.unplayedColor,
    required this.cursorColor,
    required this.waveform,
    required this.waveformLoading,
  });

  static const double _barWidth = 2.0;
  static const Radius _barRadius = Radius.circular(1);

  double _normalizedAmplitude(int index, int count) {
    final values = waveform;
    if (values == null || values.isEmpty) {
      return waveformLoading ? 0.12 : 0.35;
    }

    final sampleCount = values.length;
    final start = (index * sampleCount / count).floor();
    var end = ((index + 1) * sampleCount / count).floor();
    if (end <= start) {
      end = start + 1;
    }
    if (end > sampleCount) {
      end = sampleCount;
    }

    var peak = 0.0;
    for (var i = start; i < end; i++) {
      final value = values[i].clamp(0.0, 1.0).toDouble();
      if (value > peak) {
        peak = value;
      }
    }
    return peak;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = max(1, (size.width / 3.5).floor());
    if (barCount <= 0) return;

    final clampedFraction = fraction.clamp(0.0, 1.0).toDouble();
    final totalBarWidth = barCount * _barWidth;
    final gap = barCount > 1
        ? max(0.0, (size.width - totalBarWidth) / (barCount - 1))
        : 0.0;
    final maxHeight = size.height * 0.86;
    final minHeight = size.height * 0.14;
    final centerY = size.height / 2;
    final playedX = clampedFraction * size.width;

    final playedPaint = Paint()
      ..isAntiAlias = true
      ..color = playedColor;
    final unplayedPaint = Paint()
      ..isAntiAlias = true
      ..color = unplayedColor;

    for (var i = 0; i < barCount; i++) {
      final x = i * (_barWidth + gap);
      final amplitude =
          minHeight +
          _normalizedAmplitude(i, barCount) * (maxHeight - minHeight);
      final barLeft = x;
      final barRight = x + _barWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + _barWidth / 2, centerY),
          width: _barWidth,
          height: amplitude,
        ),
        _barRadius,
      );
      canvas.drawRRect(rect, unplayedPaint);
      if (playedX <= barLeft) continue;
      if (playedX >= barRight) {
        canvas.drawRRect(rect, playedPaint);
        continue;
      }

      // Partially fill the active bar for smoother progress indication.
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(barLeft, 0, playedX, size.height));
      canvas.drawRRect(rect, playedPaint);
      canvas.restore();
    }

    if (clampedFraction > 0 && clampedFraction < 1) {
      final cursorPaint = Paint()
        ..color = cursorColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(playedX, centerY - maxHeight / 2 - 2),
        Offset(playedX, centerY + maxHeight / 2 + 2),
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      playedColor != oldDelegate.playedColor ||
      unplayedColor != oldDelegate.unplayedColor ||
      cursorColor != oldDelegate.cursorColor ||
      waveformLoading != oldDelegate.waveformLoading ||
      !listEquals(waveform, oldDelegate.waveform);
}
