import 'package:connectivity_plus/connectivity_plus.dart';

/// Network connectivity information using `connectivity_plus`.
///
/// Provides helpers for checking the current connectivity status and listening
/// to connectivity changes.
class NetworkInfo {
  NetworkInfo(this._connectivity);

  final Connectivity _connectivity;

  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return result.isNotEmpty && !result.contains(ConnectivityResult.none);
  }

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;
}
