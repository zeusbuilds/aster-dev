import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final duoCoverLayoutProvider = StreamProvider.autoDispose<DuoCoverLayout?>(
  (ref) => DuoCoverLayout.platformUpdates,
);

/// The closed Duo's viewport and, when available, space for its tab rail.
final class DuoCoverLayout {
  const DuoCoverLayout._(this.viewport, this.railBand);

  /// Also used by the lock screen before the app's providers are mounted.
  static Stream<DuoCoverLayout?> get platformUpdates =>
      _usesNativeLayout ? _updates : const Stream.empty();

  static DuoCoverLayout? get currentPlatformLayout =>
      _usesNativeLayout ? _latest : null;

  static bool get _usesNativeLayout =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // The native channel has one event sink. Share it across the app and lock
  // covers, and replay the current geometry when another consumer appears.
  static final _platformEvents = const EventChannel(
    'com.aster.wallet/cover_navigation',
  ).receiveBroadcastStream();
  static int _listenerCount = 0;
  static DuoCoverLayout? _latest;
  static final _updates = Stream<DuoCoverLayout?>.multi((listener) {
    if (_listenerCount++ > 0) listener.add(_latest);
    final subscription = _platformEvents.listen(
      (event) {
        final layout = _fromPlatform(event);
        _latest = layout;
        listener.add(layout);
      },
      onError: (Object error, StackTrace stack) {
        _latest = null;
        listener.addError(error, stack);
      },
      onDone: listener.close,
    );
    listener.onCancel = () {
      if (--_listenerCount == 0) _latest = null;
      return subscription.cancel();
    };
  }, isBroadcast: true);

  final Size viewport;
  final Rect? railBand;

  // UIKit and Flutter can report their new sizes in separate frames on a fold.
  bool appliesTo(Size size) =>
      (size.width - viewport.width).abs() <= 1 &&
      (size.height - viewport.height).abs() <= 1;

  static DuoCoverLayout? _fromPlatform(Object? event) {
    if (event case {'width': final num width, 'height': final num height}
        when width.isFinite && width > 0 && height.isFinite && height > 0) {
      final band = switch (event) {
        {
          'left': final num left,
          'top': final num top,
          'right': final num right,
          'bottom': final num bottom,
        }
            when left.isFinite &&
                top.isFinite &&
                right.isFinite &&
                bottom.isFinite =>
          Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            right.toDouble(),
            bottom.toDouble(),
          ),
        _ => null,
      };
      return DuoCoverLayout._(Size(width.toDouble(), height.toDouble()), band);
    }
    return null;
  }
}
