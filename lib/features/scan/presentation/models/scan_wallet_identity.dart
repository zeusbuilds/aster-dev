import 'package:flutter/foundation.dart';

/// Non-secret active-wallet identity rendered by Scan presentation.
@immutable
final class ScanWalletIdentity {
  const ScanWalletIdentity({required this.name, required this.displayId});

  final String name;
  final String displayId;

  @override
  bool operator ==(Object other) =>
      other is ScanWalletIdentity &&
      other.name == name &&
      other.displayId == displayId;

  @override
  int get hashCode => Object.hash(name, displayId);
}
