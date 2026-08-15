import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_architecture.dart';

void main() {
  late Directory repository;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_architecture_');
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts the intended feature direction and adapter owners', () {
    _write(repository, 'lib/features/pay/domain/model.dart', 'class Model {}');
    _write(
      repository,
      'lib/features/pay/data/repository.dart',
      "import '../domain/model.dart';",
    );
    _write(
      repository,
      'lib/features/pay/presentation/view_model/pay_view_model.dart',
      "import '../../data/repository.dart';\n"
          'void load() { walletRepositoryProvider; clipboardServiceProvider; }',
    );
    _write(
      repository,
      'lib/features/pay/presentation/screens/pay_screen.dart',
      "import '../../domain/model.dart';\n"
          'void render(Object error, StackTrace stackTrace) { '
          'FailureMapper.from(error, stackTrace); }\n'
          'void guarded() { try {} catch (error, stackTrace) { '
          'FailureMapper.from(error, stackTrace); } }',
    );
    _write(
      repository,
      'lib/core/network/resilient_http_client.dart',
      "import 'package:http/http.dart';",
    );
    _write(
      repository,
      'lib/features/wallet/data/runtime/rgb_wallet_engine.dart',
      "import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';",
    );

    final result = verifyArchitecture(repository);

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.sourceCount, 6);
    expect(result.importCount, 5);
    expect(result.exportCount, 0);
  });

  test('applies ownership and layer policy to every export URI', () {
    _write(
      repository,
      'lib/features/pay/domain/domain.dart',
      "export '../data/repository.dart';\n"
          "export 'model.dart' if (dart.library.io) "
          "'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';",
    );
    _write(repository, 'lib/features/pay/domain/model.dart', 'class Model {}');
    _write(
      repository,
      'lib/features/pay/data/repository.dart',
      'class Repository {}',
    );
    _write(
      repository,
      'lib/features/pay/presentation/screens/pay_screen.dart',
      "export 'package:http/http.dart';",
    );

    final result = verifyArchitecture(repository);

    expect(result.passed, isFalse);
    expect(result.importCount, 0);
    expect(result.exportCount, 4);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('domain code must not depend on'),
        contains('rgb_sdk_flutter may be imported only'),
        contains('package:http is infrastructure'),
      ]),
    );
  });

  test('requires complete value semantics on presentation state models', () {
    _write(
      repository,
      'lib/features/pay/presentation/models/good_state.dart',
      'final class GoodState {\n'
          '  @override\n'
          '  bool operator ==(Object other) => identical(this, other);\n'
          '  @override\n'
          '  int get hashCode => 0;\n'
          '}',
    );
    _write(
      repository,
      'lib/features/pay/presentation/models/missing_equality_state.dart',
      'final class MissingEqualityState {\n'
          '  @override\n'
          '  int get hashCode => 0;\n'
          '}',
    );
    _write(
      repository,
      'lib/features/pay/presentation/models/missing_hash_state.dart',
      'final class MissingHashState {\n'
          '  @override\n'
          '  bool operator ==(Object other) => identical(this, other);\n'
          '}',
    );
    _write(
      repository,
      'lib/features/pay/domain/domain_state.dart',
      'final class DomainState {}',
    );
    _write(
      repository,
      'lib/shared/feedback/missing_shared_state.dart',
      '@immutable\nfinal class MissingSharedState {}',
    );

    final result = verifyArchitecture(repository);

    expect(result.passed, isFalse);
    expect(result.failures, hasLength(3));
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('MissingEqualityState must declare operator =='),
        contains('MissingHashState must declare hashCode'),
        contains('MissingSharedState must declare operator == and hashCode'),
      ]),
    );
  });

  test('requires presentation to consume the full reconciliation contract', () {
    _write(
      repository,
      'lib/features/pay/presentation/models/pay_model.dart',
      'bool blocksPayment(dynamic failure) => '
          'failure.requiresReconciliation == true;',
    );
    _write(
      repository,
      'lib/features/pay/presentation/screens/pay_screen.dart',
      'bool blocksPayment(dynamic failure) => failure.outcomeUnknown == true;',
    );
    _write(
      repository,
      'lib/features/pay/presentation/view_model/pay_view_model.dart',
      'bool blocksPayment(dynamic failure) => failure.outcomeUnknown == true;',
    );

    final result = verifyArchitecture(repository);

    expect(result.passed, isFalse);
    expect(result.failures, hasLength(2));
    expect(
      result.failures,
      everyElement(
        allOf(
          contains('feature presentation must use requiresReconciliation'),
          contains('diagnostic outcomeUnknown subset'),
        ),
      ),
    );
  });

  test('reports every layer, SDK, plugin, and parse violation', () {
    _write(
      repository,
      'lib/features/pay/domain/model.dart',
      "import '../data/repository.dart';",
    );
    _write(
      repository,
      'lib/features/pay/data/repository.dart',
      "import '../presentation/screens/pay_screen.dart';",
    );
    _write(
      repository,
      'lib/features/pay/presentation/screens/pay_screen.dart',
      "import '../../data/repository.dart';\n"
          "import 'package:http/http.dart';\n"
          "import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';\n"
          'void submit() { '
          'walletRepositoryProvider; clipboardServiceProvider; }\n'
          'void render(Object error) { '
          'FailureMapper.from(error, StackTrace.current); }\n'
          'void discard() { try {} catch (_) {} }',
    );
    _write(repository, 'lib/broken.dart', "import 'unterminated.dart;");

    final result = verifyArchitecture(repository);

    expect(result.passed, isFalse);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('domain code must not depend on'),
        contains('data code must not depend on presentation'),
        contains('presentation outside a ViewModel'),
        contains('package:http is infrastructure'),
        contains('rgb_sdk_flutter may be imported only'),
        contains('walletRepositoryProvider intent through a ViewModel'),
        contains('clipboardServiceProvider intent through a ViewModel'),
        contains('must pass the captured failure stack'),
        contains('must capture and map thrown exceptions'),
        contains('parse error:'),
      ]),
    );
  });

  test('fails closed when the repository has no lib directory', () {
    final result = verifyArchitecture(repository);

    expect(result.passed, isFalse);
    expect(result.sourceCount, 0);
    expect(result.exportCount, 0);
    expect(result.failures.single, contains('Missing lib directory'));
  });
}

void _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$contents\n');
}
