import 'package:flutter/foundation.dart';

import '../../../../core/errors/errors.dart';

/// Root presentation state for serialized native wallet lifecycle changes.
@immutable
final class WalletLifecycleState {
  const WalletLifecycleState({
    this.obscured = false,
    this.transitioning = false,
    this.foregroundGeneration = 0,
    this.failure,
  }) : assert(foregroundGeneration >= 0);

  /// Whether application content must remain hidden for system privacy.
  final bool obscured;

  /// Whether a native suspend, resume, or disposal command is in flight.
  final bool transitioning;

  /// Increments after each confirmed foreground resume.
  ///
  /// Read-only wallet projections watch this value so they reload after the
  /// native store has been reopened without discarding in-progress send forms.
  final int foregroundGeneration;

  /// Latest lifecycle failure, retained while a user-initiated retry runs.
  final AppFailure? failure;

  /// Whether content must reject input and be excluded from semantics.
  bool get blocksInteraction => obscured || transitioning || failure != null;

  /// Whether the privacy splash, rather than an actionable failure, is shown.
  bool get showsPrivacySplash => obscured || (transitioning && failure == null);

  /// Whether a foreground failure should replace the wallet UI.
  bool get showsFailure => !obscured && failure != null;

  @override
  bool operator ==(Object other) =>
      other is WalletLifecycleState &&
      other.obscured == obscured &&
      other.transitioning == transitioning &&
      other.foregroundGeneration == foregroundGeneration &&
      other.failure == failure;

  @override
  int get hashCode =>
      Object.hash(obscured, transitioning, foregroundGeneration, failure);
}
