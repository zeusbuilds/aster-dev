/// State for the scan screen (flash, permission, error).
/// Zoom is driven by device lens range in [ScanScreen] (zoom factors from camera min/max).
class ScanState {
  const ScanState({
    this.flashOn = false,
    this.permissionDenied = false,
    this.errorMessage,
  });

  final bool flashOn;
  final bool permissionDenied;
  final String? errorMessage;

  ScanState copyWith({
    bool? flashOn,
    bool? permissionDenied,
    Object? errorMessage = _unset,
  }) {
    return ScanState(
      flashOn: flashOn ?? this.flashOn,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _unset = Object();
