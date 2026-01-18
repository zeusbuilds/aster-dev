import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'skeleton_index_provider.g.dart';

/// Provider for managing the current bottom navigation index
/// Tracks which screen is currently active in the skeleton navigation
@riverpod
class SkeletonIndex extends _$SkeletonIndex {
  @override
  int build() => 0;

  /// Sets the current navigation index
  /// [index] - The index of the screen to navigate to (0-3)
  void setIndex(int index) {
    state = index;
  }
}
