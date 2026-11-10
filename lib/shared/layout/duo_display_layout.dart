import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final duoDisplayLayoutProvider = StreamProvider.autoDispose<DuoDisplayLayout?>(
  (ref) => DuoDisplayLayout.platformUpdates,
);

/// Keeps the cover-only consumers independent of inner-display changes.
final duoCoverLayoutProvider =
    Provider.autoDispose<AsyncValue<DuoDisplayLayout?>>(
      (ref) => ref
          .watch(duoDisplayLayoutProvider)
          .whenData((layout) => layout?.isCover == true ? layout : null),
    );

/// The active Duo display's viewport and its optional tab rail space.
final class DuoDisplayLayout {
  const DuoDisplayLayout._(
    this.viewport,
    this.railBand, {
    required this.isCover,
  });

  /// Also used by the lock screen before the app's providers are mounted.
  static Stream<DuoDisplayLayout?> get platformUpdates =>
      _usesNativeLayout ? _updates : const Stream.empty();

  static DuoDisplayLayout? get currentPlatformLayout =>
      _usesNativeLayout ? _latest : null;

  static bool get _usesNativeLayout =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  // The native channel has one event sink. Share it across the app and lock
  // covers, and replay the current geometry when another consumer appears.
  static final _platformEvents = const EventChannel(
    'com.aster.wallet/cover_navigation',
  ).receiveBroadcastStream();
  static int _listenerCount = 0;
  static DuoDisplayLayout? _latest;
  static final _updates = Stream<DuoDisplayLayout?>.multi((listener) {
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
  final bool isCover;

  // UIKit and Flutter can report their new sizes in separate frames on a fold.
  bool appliesTo(Size size) =>
      (size.width - viewport.width).abs() <= 1 &&
      (size.height - viewport.height).abs() <= 1;

  bool isOpenLandscapeFor(Size size) =>
      !isCover && size.width > size.height && appliesTo(size);

  static DuoDisplayLayout? _fromPlatform(Object? event) {
    if (event case {'width': final num width, 'height': final num height}
        when width.isFinite && width > 0 && height.isFinite && height > 0) {
      final viewport = Size(width.toDouble(), height.toDouble());
      final isCover = switch (event) {
        {'inner': true} => false,
        _ => true,
      };
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
      return DuoDisplayLayout._(viewport, band, isCover: isCover);
    }
    return null;
  }
}
