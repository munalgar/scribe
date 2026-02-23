import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app obtains its backend server.
enum BackendMode {
  /// The app manages a bundled backend process automatically.
  managed,

  /// The user runs the backend themselves (dev workflow or remote server).
  external,
}

class AppPreferences extends ChangeNotifier {
  final SharedPreferences _prefs;

  static const _keyLanguage = 'default_language';
  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const _keyBackendMode = 'backend_mode';
  static const _keyDevMode = 'dev_mode';

  static const defaultHost = '127.0.0.1';
  static const defaultPort = 50051;

  AppPreferences(this._prefs);

  // -- Default language (null = auto-detect) --

  String? get defaultLanguage => _prefs.getString(_keyLanguage);

  Future<void> setDefaultLanguage(String? value) async {
    if (value == null) {
      await _prefs.remove(_keyLanguage);
    } else {
      await _prefs.setString(_keyLanguage, value);
    }
    notifyListeners();
  }

  // -- Server connection --

  /// Effective host: env var > saved pref > default.
  String get serverHost {
    final envHost = _envHost;
    if (envHost != null && envHost.isNotEmpty) return envHost;
    return _prefs.getString(_keyHost) ?? defaultHost;
  }

  /// Effective port: env var > saved pref > default.
  int get serverPort {
    final envPort = _envPort;
    if (envPort != null) return envPort;
    return _prefs.getInt(_keyPort) ?? defaultPort;
  }

  /// Whether the current host/port came from environment variables.
  bool get isEnvOverride => _envHost != null || _envPort != null;

  Future<void> setServerConnection(String host, int port) async {
    await _prefs.setString(_keyHost, host);
    await _prefs.setInt(_keyPort, port);
    notifyListeners();
  }

  /// Reset server connection to defaults (clears saved prefs).
  Future<void> resetServerConnection() async {
    await _prefs.remove(_keyHost);
    await _prefs.remove(_keyPort);
    notifyListeners();
  }

  // -- Backend mode --

  /// How the backend is provided.
  ///
  /// Defaults to [BackendMode.managed] in release builds (bundled binary) and
  /// [BackendMode.external] in debug builds (developer runs it manually).
  BackendMode get backendMode {
    final stored = _prefs.getString(_keyBackendMode);
    if (stored != null) {
      return BackendMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => _defaultBackendMode,
      );
    }
    return _defaultBackendMode;
  }

  Future<void> setBackendMode(BackendMode mode) async {
    await _prefs.setString(_keyBackendMode, mode.name);
    notifyListeners();
  }

  static BackendMode get _defaultBackendMode =>
      kDebugMode ? BackendMode.external : BackendMode.managed;

  // -- Developer mode --

  /// Whether the advanced / developer UI is visible.
  ///
  /// Defaults to `false`.  Can be turned on from Settings.
  bool get devMode {
    return _prefs.getBool(_keyDevMode) ?? false;
  }

  Future<void> setDevMode(bool value) async {
    await _prefs.setBool(_keyDevMode, value);
    notifyListeners();
  }

  // -- Environment variable helpers --

  static String? get _envHost {
    try {
      final v = Platform.environment['SCRIBE_BACKEND_HOST'];
      return (v != null && v.isNotEmpty) ? v : null;
    } catch (_) {
      return null;
    }
  }

  static int? get _envPort {
    try {
      final v = Platform.environment['SCRIBE_BACKEND_PORT'];
      if (v == null || v.isEmpty) return null;
      return int.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  /// True when running from a debug/assert-enabled build (dev mode).
  static bool get isDevMode => kDebugMode;
}
