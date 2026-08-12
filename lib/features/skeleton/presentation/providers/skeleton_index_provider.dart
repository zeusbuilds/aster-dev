import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'skeleton_index_provider.g.dart';

/// Number of stable destinations in the app shell.
const int skeletonTabCount = 4;

/// Index of the Scan destination in the app shell.
const int skeletonScanTabIndex = 1;

/// Provider for managing the current bottom navigation index
///
/// Tracks which screen is currently active in the skeleton navigation
@riverpod
class SkeletonIndex extends _$SkeletonIndex {
  @override
  int build() => 0;

  /// Selects one of the stable app-shell destinations.
  ///
  /// Invalid indices fail synchronously and never mutate the current state.
  void setIndex(int index) {
    if (index < 0 || index >= skeletonTabCount) {
      throw RangeError.range(index, 0, skeletonTabCount - 1, 'index');
    }
    state = index;
  }
}
