import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show MediaQueryData;
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

  // Measured against the native status indicators on both Duo displays.
  static const _statusAxisInset = 6.0;

  // UIKit and Flutter can report their new sizes in separate frames on a fold.
  bool appliesTo(Size size) =>
      (size.width - viewport.width).abs() <= 1 &&
      (size.height - viewport.height).abs() <= 1;

  bool isOpenLandscapeFor(Size size) =>
      !isCover && size.width > size.height && appliesTo(size);

  /// Space for vertical controls and the system status column's centerline.
  ({Rect bounds, double centerX})? availableRailFor(MediaQueryData media) {
    final size = media.size;
    final band = railBand;
    if (band == null ||
        !(isCover ? appliesTo(size) : isOpenLandscapeFor(size))) {
      return null;
    }

    final padding = media.viewPadding;
    final obscured = media.viewInsets;
    final onRight = isCover || band.center.dx >= size.width / 2;
    final left = math.max(
      band.left,
      onRight ? size.width - padding.right : obscured.left,
    );
    final right = math.min(
      band.right,
      onRight ? size.width - obscured.right : padding.left,
    );
    final top = isCover
        ? math.max(0.0, band.top)
        : math.max(band.top, math.max(padding.top, obscured.top));
    final bottom = math.min(
      band.bottom,
      size.height - math.max(padding.bottom, obscured.bottom),
    );
    if (left >= right || top >= bottom) return null;
    return (
      bounds: Rect.fromLTRB(left, top, right, bottom),
      centerX:
          band.center.dx + (onRight ? -_statusAxisInset : _statusAxisInset),
    );
  }

  /// One half of the inner display with the Welcome side gutters removed.
  double? actionMaxWidthFor(Size size, double sideGutter) =>
      isOpenLandscapeFor(size)
      ? _halfScreenActionWidth(size, sideGutter)
      : null;

  /// Overlays can use the viewport immediately, even while native fold
  /// geometry catches up. Aster's supported iPhone landscape is the Duo inner
  /// display.
  static double? landscapeOverlayMaxWidth(Size size, double sideGutter) =>
      _usesNativeLayout && size.width > size.height
      ? _halfScreenActionWidth(size, sideGutter)
      : null;

  static double _halfScreenActionWidth(Size size, double sideGutter) =>
      math.max(0.0, size.width / 2 - 2 * sideGutter);

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
