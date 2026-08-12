import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';

/// Opaque platform-camera surface for one purpose-scoped Scan session.
///
/// Plugin widgets and controllers remain inside the injected session adapter.
class ScanCamera extends ConsumerWidget {
  const ScanCamera({
    super.key,
    required this.purpose,
    required this.cutoutRect,
    required this.placeholderColor,
    required this.onCaptured,
  });

  final ScanPurpose purpose;
  final Rect cutoutRect;
  final Color placeholderColor;
  final ValueChanged<ScanPayload> onCaptured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(scanSessionProvider(purpose));
    return session.buildCameraSurface(
      scanWindow: cutoutRect,
      placeholderColor: placeholderColor,
      onCaptured: onCaptured,
    );
  }
}
