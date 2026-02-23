import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The lifecycle state of the managed backend process.
enum BackendProcessState {
  /// No process is running and none has been requested.
  stopped,

  /// The process is being started (spawned, waiting for the SCRIBE_READY
  /// marker on stdout).
  starting,

  /// The process is running and the ready marker has been received.
  running,

  /// The process exited unexpectedly and we are about to restart it.
  crashed,
}

/// Manages the lifecycle of the bundled Python backend binary.
///
/// In a **release** build the backend executable lives inside the app bundle:
///   • macOS:  `<bundle>/Contents/Resources/scribe_backend/scribe_backend`
///   • Linux:  `<app-dir>/lib/scribe_backend/scribe_backend`
///   • Windows: `<app-dir>\scribe_backend\scribe_backend.exe`
///
/// In a **debug** build (dev mode) the manager is not used — the developer
/// runs the backend manually (or via `scripts/dev_backend.sh`).
class BackendProcessManager extends ChangeNotifier {
  Process? _process;
  BackendProcessState _state = BackendProcessState.stopped;
  int? _port;
  int _crashCount = 0;

  /// Rolling buffer of the last N lines of backend output (for diagnostics).
  final List<String> _logBuffer = [];
  static const _maxLogLines = 200;

  BackendProcessState get state => _state;

  /// The port the backend is listening on, or null if not yet known.
  int? get port => _port;

  /// True when the process is running and reported ready.
  bool get isRunning => _state == BackendProcessState.running;

  /// How many times the process crashed since the last successful start.
  int get crashCount => _crashCount;

  /// Recent log lines from the backend process (newest last).
  List<String> get logs => List.unmodifiable(_logBuffer);

  /// A human-readable label for the current state.
  String get stateLabel => switch (_state) {
    BackendProcessState.stopped => 'Stopped',
    BackendProcessState.starting => 'Starting…',
    BackendProcessState.running => 'Running (port $_port)',
    BackendProcessState.crashed => 'Crashed — restarting…',
  };

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the backend process.
  ///
  /// Finds a free port, spawns the executable, and waits for the ready marker
  /// (`SCRIBE_READY port=<N>`) on stdout.  Returns the port on success, or
  /// throws on failure.
  ///
  /// In release builds the bundled binary is used.  In debug builds, if the
  /// binary is not found, the manager falls back to running the Python backend
  /// directly (`python -m scribe_backend.server`), mirroring what
  /// `scripts/dev_backend.sh` does.
  Future<int> start() async {
    if (_state == BackendProcessState.running ||
        _state == BackendProcessState.starting) {
      return _port!;
    }

    _state = BackendProcessState.starting;
    notifyListeners();

    // Pick a free TCP port.
    final freePort = await _findFreePort();

    final exePath = _resolveExecutablePath();

    if (exePath != null) {
      // ── Compiled binary path ──────────────────────────────────────────
      _log('[manager] Starting backend on port $freePort');
      _log('[manager] Executable: $exePath');

      try {
        _process = await Process.start(exePath, [
          '--port',
          '$freePort',
        ], mode: ProcessStartMode.normal);
      } catch (e) {
        _state = BackendProcessState.stopped;
        notifyListeners();
        throw StateError('Failed to start backend process: $e');
      }
    } else if (kDebugMode) {
      // ── Dev-mode fallback: run the Python backend directly ────────────
      final devPaths = _resolveDevPythonPaths();
      if (devPaths == null) {
        _state = BackendProcessState.stopped;
        notifyListeners();
        throw StateError(
          'Could not find the Python backend sources or a suitable Python '
          'interpreter.\n'
          'Make sure a virtual environment exists at .venv/ (run '
          'scripts/dev_backend.sh once) and that the backend/ directory is '
          'present in the project root.',
        );
      }

      final (String python, String backendDir) = devPaths;
      _log('[manager] Dev mode — starting Python backend on port $freePort');
      _log('[manager] Python: $python');
      _log('[manager] Working dir: $backendDir');

      try {
        _process = await Process.start(
          python,
          ['-m', 'scribe_backend.server', '--port', '$freePort'],
          workingDirectory: backendDir,
          mode: ProcessStartMode.normal,
        );
      } catch (e) {
        _state = BackendProcessState.stopped;
        notifyListeners();
        throw StateError('Failed to start Python backend: $e');
      }
    } else {
      _state = BackendProcessState.stopped;
      notifyListeners();
      throw StateError(
        'Backend executable not found. '
        'Run scripts/build_backend.sh to build it, or start the backend '
        'manually with scripts/dev_backend.sh.',
      );
    }

    // Listen to stdout for the ready marker.
    final readyCompleter = Completer<int>();

    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log(line);
          if (!readyCompleter.isCompleted && line.contains('SCRIBE_READY')) {
            // Parse "SCRIBE_READY port=<N>"
            final match = RegExp(r'port=(\d+)').firstMatch(line);
            final port = match != null ? int.parse(match.group(1)!) : freePort;
            readyCompleter.complete(port);
          }
        });

    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _log('[stderr] $line');
        });

    // Handle unexpected exit.
    _process!.exitCode.then((code) {
      if (_state == BackendProcessState.running ||
          _state == BackendProcessState.starting) {
        _log('[manager] Process exited with code $code');
        _state = BackendProcessState.crashed;
        _crashCount++;
        _process = null;
        notifyListeners();
      }
    });

    // Wait for the ready marker (with a timeout).
    try {
      _port = await readyCompleter.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      await stop();
      throw StateError(
        'Backend did not become ready within 30 seconds. '
        'Check the logs in Settings → Server for details.',
      );
    }

    _state = BackendProcessState.running;
    _crashCount = 0;
    notifyListeners();
    _log('[manager] Backend ready on port $_port');
    return _port!;
  }

  /// Stop the backend process gracefully.
  Future<void> stop() async {
    if (_process == null) {
      _state = BackendProcessState.stopped;
      notifyListeners();
      return;
    }

    _log('[manager] Stopping backend…');

    // Send SIGTERM (graceful shutdown).
    _process!.kill(ProcessSignal.sigterm);

    // Give it 5 seconds, then SIGKILL.
    try {
      await _process!.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _log('[manager] Force-killing backend');
      _process!.kill(ProcessSignal.sigkill);
    }

    _process = null;
    _port = null;
    _state = BackendProcessState.stopped;
    notifyListeners();
  }

  /// Restart the backend process (stop + start).
  Future<int> restart() async {
    await stop();
    return start();
  }

  // ---------------------------------------------------------------------------
  // Path resolution
  // ---------------------------------------------------------------------------

  /// Locate the bundled backend executable based on the platform.
  ///
  /// Returns null if the executable is not found (e.g. dev mode without a
  /// build, or unsupported platform).
  static String? _resolveExecutablePath() {
    final exeName = Platform.isWindows
        ? 'scribe_backend.exe'
        : 'scribe_backend';

    // Candidate paths, in priority order.
    final candidates = <String>[];

    if (Platform.isMacOS) {
      // Inside macOS .app bundle: <bundle>/Contents/Resources/scribe_backend/
      final bundlePath =
          Platform.resolvedExecutable; // .../Contents/MacOS/scribe_app
      final resourcesDir = p.join(
        p.dirname(p.dirname(bundlePath)), // .../Contents
        'Resources',
        'scribe_backend',
      );
      candidates.add(p.join(resourcesDir, exeName));
    } else if (Platform.isLinux) {
      final appDir = p.dirname(Platform.resolvedExecutable);
      candidates.add(p.join(appDir, 'lib', 'scribe_backend', exeName));
      candidates.add(p.join(appDir, 'scribe_backend', exeName));
    } else if (Platform.isWindows) {
      final appDir = p.dirname(Platform.resolvedExecutable);
      candidates.add(p.join(appDir, 'scribe_backend', exeName));
    }

    // Fallback: look relative to the project root (for development).
    // When running via `flutter run`, resolvedExecutable is deep in the
    // build tree, so walk up looking for backend/dist/.
    final devDist = _findDevDistPath();
    if (devDist != null) {
      candidates.add(p.join(devDist, exeName));
    }

    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Walk up from the resolved executable to find `backend/dist/scribe_backend`
  /// for development builds.
  static String? _findDevDistPath() {
    // Start from the current working directory (project root when using
    // `flutter run`).
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final candidate = p.join(dir.path, 'backend', 'dist', 'scribe_backend');
      if (Directory(candidate).existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached fs root
      dir = parent;
    }
    return null;
  }

  /// Locate the Python interpreter and the `backend/` working directory so
  /// we can run `python -m scribe_backend.server` in dev mode.
  ///
  /// Returns `(pythonPath, backendDir)` or `null` if the layout can't be
  /// found.
  static (String, String)? _resolveDevPythonPaths() {
    // Walk up from cwd looking for the project root (identified by the
    // presence of `backend/scribe_backend/server.py`).
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
      final serverPy = File(
        p.join(dir.path, 'backend', 'scribe_backend', 'server.py'),
      );
      if (serverPy.existsSync()) {
        final backendDir = p.join(dir.path, 'backend');

        // Prefer the project's virtual-env Python.
        final venvCandidates = [
          p.join(dir.path, '.venv', 'bin', 'python'), // macOS / Linux
          p.join(dir.path, '.venv', 'Scripts', 'python.exe'), // Windows
        ];
        for (final venv in venvCandidates) {
          if (File(venv).existsSync()) return (venv, backendDir);
        }

        // Fall back to the system Python.
        final sysCandidates = Platform.isWindows
            ? ['python.exe', 'python3.exe']
            : ['python3', 'python'];
        for (final name in sysCandidates) {
          final result = Process.runSync('which', [name]);
          if (result.exitCode == 0) {
            final path = (result.stdout as String).trim();
            if (path.isNotEmpty) return (path, backendDir);
          }
        }

        return null; // found the project but no Python
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Find a free TCP port by binding to port 0.
  static Future<int> _findFreePort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    return port;
  }

  void _log(String line) {
    _logBuffer.add(line);
    if (_logBuffer.length > _maxLogLines) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxLogLines);
    }
    // In debug mode, also forward to the debug console.
    if (kDebugMode) {
      debugPrint('[scribe-backend] $line');
    }
  }

  @override
  void dispose() {
    // Fire-and-forget — we're shutting down.
    stop();
    super.dispose();
  }
}
