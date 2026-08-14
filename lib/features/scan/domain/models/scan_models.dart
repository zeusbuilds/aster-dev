import 'package:flutter/foundation.dart';

import '../../../../core/validation/validation.dart';

/// Why a Scan surface is active.
///
/// A persistent launcher cannot return a value to a caller, while a destination
/// picker is expected to complete exactly one pushed route.
enum ScanPurpose { sendLauncher, destinationPicker }

/// Where a bounded scan payload originated.
enum ScanCaptureSource { camera, gallery }

/// A bounded, potentially sensitive QR payload held only long enough for Send.
///
/// The payload is intentionally excluded from [toString] so provider and error
/// diagnostics cannot disclose addresses, invoices, labels, or payment hashes.
@immutable
final class ScanPayload {
  ScanPayload.parse(String raw, {required this.source}) : value = raw.trim() {
    if (!ProtocolTextPolicy.isVisibleAscii(
      value,
      maximumCharacters: maximumCharacters,
    )) {
      throw const InvalidScanPayloadException();
    }
  }

  /// Maximum input accepted by the app's payment-preview boundary.
  static const int maximumCharacters = 8192;

  final String value;
  final ScanCaptureSource source;

  @override
  String toString() => 'ScanPayload(${source.name})';

  @override
  bool operator ==(Object other) =>
      other is ScanPayload && other.value == value && other.source == source;

  @override
  int get hashCode => Object.hash(value, source);
}

/// Redacted marker for an empty, oversized, or unsafe scanner payload.
final class InvalidScanPayloadException implements Exception {
  const InvalidScanPayloadException();

  @override
  String toString() => 'InvalidScanPayloadException';
}

/// Result of an explicit gallery-selection operation.
sealed class ScanGalleryOutcome {
  const ScanGalleryOutcome();
}

/// The system picker was dismissed without selecting an image.
final class ScanGalleryCancelled extends ScanGalleryOutcome {
  const ScanGalleryCancelled();
}

/// The selected image contained no supported QR payload.
final class ScanGalleryNoCode extends ScanGalleryOutcome {
  const ScanGalleryNoCode();
}

/// The selected image contained one bounded QR payload.
final class ScanGalleryCaptured extends ScanGalleryOutcome {
  const ScanGalleryCaptured(this.payload);

  final ScanPayload payload;
}
