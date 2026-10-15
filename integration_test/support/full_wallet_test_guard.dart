import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'full_wallet_qa.dart';

/// An uncaught async callback can end the driver and clear takeException while
/// the test body is still alive. Retain that failure independently of its slot.
final class FullWalletQaFrameworkErrorLatch {
  var _failed = false;

  void notice() => _failed = true;

  void requireHealthy(WidgetTester tester) {
    if (_failed || !tester.binding.inTest || tester.takeException() != null) {
      _failed = true;
      throw const FullWalletQaFailure('qa_framework_async_error');
    }
  }
}

/// Observe the binding's existing error hook before it clears pending details.
/// Super retains normal framework reporting and integration-driver failure.
final class FullWalletQaIntegrationBinding
    extends IntegrationTestWidgetsFlutterBinding {
  final frameworkErrors = FullWalletQaFrameworkErrorLatch();

  @override
  void reportExceptionNoticed(FlutterErrorDetails exception) {
    frameworkErrors.notice();
    super.reportExceptionNoticed(exception);
  }
}

void requireQaFrameworkHealthy(WidgetTester tester) {
  final binding = tester.binding;
  if (binding is FullWalletQaIntegrationBinding) {
    binding.frameworkErrors.requireHealthy(tester);
    return;
  }
  // Unit tests use their existing automated binding. Native qualification must
  // instantiate FullWalletQaIntegrationBinding before testWidgets is invoked.
  if (!binding.inTest || tester.takeException() != null) {
    throw const FullWalletQaFailure('qa_framework_async_error');
  }
}
