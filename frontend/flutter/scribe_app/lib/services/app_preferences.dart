import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  final SharedPreferences _prefs;

  static const _keyLanguage = 'default_language';
  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';

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

  String get serverHost => _prefs.getString(_keyHost) ?? defaultHost;

  int get serverPort => _prefs.getInt(_keyPort) ?? defaultPort;

  Future<void> setServerConnection(String host, int port) async {
    await _prefs.setString(_keyHost, host);
    await _prefs.setInt(_keyPort, port);
    notifyListeners();
  }
}
