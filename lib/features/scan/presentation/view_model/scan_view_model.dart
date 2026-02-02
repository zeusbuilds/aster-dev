import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'scan_state.dart';

part 'scan_view_model.g.dart';

/// ViewModel for scan screen: flash/zoom state and permission/error feedback.
@riverpod
class ScanViewModel extends _$ScanViewModel {
  @override
  ScanState build() => const ScanState();

  void toggleFlash() {
    state = state.copyWith(flashOn: !state.flashOn);
  }

  /// Turn flash off (e.g. when leaving scan tab so UI matches actual flash state).
  void setFlash(bool on) {
    state = state.copyWith(flashOn: on);
  }

  void setPermissionDenied(bool denied) {
    state = state.copyWith(permissionDenied: denied);
  }

  void setError(String? message) {
    state = state.copyWith(errorMessage: message);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
