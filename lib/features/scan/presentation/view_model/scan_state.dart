import 'package:freezed_annotation/freezed_annotation.dart';

part 'scan_state.freezed.dart';

/// State for the scan screen (flash, permission, error).
/// Zoom is driven by device lens range in [ScanScreen] (zoom factors from camera min/max).
@freezed
class ScanState with _$ScanState {
  const factory ScanState({
    /// Whether the torch/flash is on.
    @Default(false) bool flashOn,

    /// Whether camera permission was denied.
    @Default(false) bool permissionDenied,

    /// Error message to show (e.g. init failure, no camera).
    String? errorMessage,
  }) = _ScanState;
}
