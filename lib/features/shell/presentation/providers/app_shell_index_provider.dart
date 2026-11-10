import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_shell_index_provider.g.dart';

/// Number of stable destinations in the app shell.
const int appShellTabCount = 4;

/// Index of the Scan destination in the app shell.
const int appShellScanTabIndex = 1;

/// Index of the Settings destination in the app shell.
const int appShellSettingsTabIndex = 3;

/// Owns the selected destination in the persistent application shell.
@riverpod
class AppShellIndex extends _$AppShellIndex {
  @override
  int build() => 0;

  /// Selects one of the stable app-shell destinations.
  ///
  /// Invalid indices fail synchronously and never mutate the current state.
  void setIndex(int index) {
    if (index < 0 || index >= appShellTabCount) {
      throw RangeError.range(index, 0, appShellTabCount - 1, 'index');
    }
    state = index;
  }
}
