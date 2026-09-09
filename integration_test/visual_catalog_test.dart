import 'package:integration_test/integration_test.dart';

import '../test/support/visual_catalog.dart';

/// iOS simulator screenshots of production widgets with isolated UI fixtures.
/// Never runs the native wallet or accesses an installed wallet's storage.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerVisualCatalog(
    capture: (tester, name) async {
      // flutter test removes its simulator container on completion. The
      // extended host driver exports these before that cleanup occurs.
      await binding.takeScreenshot(name);
    },
  );
}
