import 'dart:async';
import 'dart:io';
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

  Future<void> connect({String? host, int? port}) async {
    if (host != null) _host = host;
    if (port != null) _port = port;
    if (_state == BackendConnectionState.connecting) return;
    _state = BackendConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _client.connect(host: _host, port: _port);
      final response = await _client.healthCheck();
      if (response.ok) {
        _state = BackendConnectionState.connected;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      } else {
        _state = BackendConnectionState.error;
        _errorMessage = response.message;
      }
    } on GrpcError catch (e) {
      _state = BackendConnectionState.error;
      _errorMessage = e.message ?? 'Connection failed';
      _scheduleReconnect();
    } on SocketException catch (e) {
      _state = BackendConnectionState.error;
      _errorMessage = e.message;
      _scheduleReconnect();
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
