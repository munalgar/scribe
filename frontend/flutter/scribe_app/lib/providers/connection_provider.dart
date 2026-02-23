import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import '../services/grpc_client.dart';

enum BackendConnectionState { disconnected, connecting, connected, error }

class ConnectionProvider extends ChangeNotifier {
  final ScribeGrpcClient _client = ScribeGrpcClient();
  BackendConnectionState _state = BackendConnectionState.disconnected;
  String? _errorMessage;
  Timer? _reconnectTimer;

  BackendConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  ScribeGrpcClient get client => _client;

  String _host = '127.0.0.1';
  int _port = 50051;

  String get host => _host;
  int get port => _port;

  /// Number of consecutive failed connection attempts.
  int _reconnectAttempts = 0;
  int get reconnectAttempts => _reconnectAttempts;

  /// Whether auto-reconnect is enabled.
  bool _autoReconnect = true;
  bool get autoReconnect => _autoReconnect;
  set autoReconnect(bool value) {
    _autoReconnect = value;
    if (!value) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
    notifyListeners();
  }

  /// Last measured round-trip latency in milliseconds, or null.
  int? _latencyMs;
  int? get latencyMs => _latencyMs;

  /// A human-readable status message for the current state.
  String get statusMessage => switch (_state) {
    BackendConnectionState.connected => 'Connected to $_host:$_port',
    BackendConnectionState.connecting =>
      _reconnectAttempts > 0
          ? 'Reconnecting… (attempt $_reconnectAttempts)'
          : 'Connecting to $_host:$_port…',
    BackendConnectionState.error => _errorMessage ?? 'Connection failed',
    BackendConnectionState.disconnected => 'Not connected',
  };

  /// Address string for display.
  String get address => '$_host:$_port';

  Future<void> connect({String? host, int? port}) async {
    if (host != null) _host = host;
    if (port != null) _port = port;
    if (_state == BackendConnectionState.connecting) return;
    _state = BackendConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _client.connect(host: _host, port: _port);
      final sw = Stopwatch()..start();
      final response = await _client.healthCheck();
      sw.stop();
      if (response.ok) {
        _state = BackendConnectionState.connected;
        _latencyMs = sw.elapsedMilliseconds;
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      } else {
        _state = BackendConnectionState.error;
        _errorMessage = response.message;
        _latencyMs = null;
        _reconnectAttempts++;
        _scheduleReconnect();
      }
    } on GrpcError catch (e) {
      _state = BackendConnectionState.error;
      _errorMessage = _friendlyError(e.message ?? 'Connection refused');
      _latencyMs = null;
      _reconnectAttempts++;
      _scheduleReconnect();
    } on SocketException catch (e) {
      _state = BackendConnectionState.error;
      _errorMessage = _friendlyError(e.message);
      _latencyMs = null;
      _reconnectAttempts++;
      _scheduleReconnect();
    } catch (e) {
      _state = BackendConnectionState.error;
      _errorMessage = _friendlyError(e.toString());
      _latencyMs = null;
      _reconnectAttempts++;
      _scheduleReconnect();
    }
    notifyListeners();
  }

  /// One-shot connection test. Returns latency in ms on success, or throws.
  Future<int> testConnection(String host, int port) async {
    final testClient = ScribeGrpcClient();
    try {
      await testClient.connect(host: host, port: port);
      final sw = Stopwatch()..start();
      final response = await testClient.healthCheck();
      sw.stop();
      if (!response.ok) {
        throw Exception(response.message);
      }
      return sw.elapsedMilliseconds;
    } finally {
      await testClient.disconnect();
    }
  }

  /// Reconnect immediately, resetting the attempt counter.
  Future<void> retry() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await connect();
  }

  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    _reconnectTimer?.cancel();
    // Exponential backoff: 2s, 4s, 8s, 16s, capped at 30s.
    final delaySec = math
        .min(30, 2 * math.pow(2, math.min(_reconnectAttempts - 1, 4)))
        .toInt();
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }

  /// Returns a user-friendly error message.
  static String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('connection refused') ||
        lower.contains('errno = 61') ||
        lower.contains('errno = 111')) {
      return 'Backend server is not running';
    }
    if (lower.contains('deadline exceeded') || lower.contains('timeout')) {
      return 'Connection timed out';
    }
    if (lower.contains('dns') ||
        lower.contains('host not found') ||
        lower.contains('getaddrinfo')) {
      return 'Host not found — check the address';
    }
    return raw;
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _latencyMs = null;
    await _client.disconnect();
    _state = BackendConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _client.disconnect();
    super.dispose();
  }
}
