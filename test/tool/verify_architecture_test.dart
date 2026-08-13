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
    expect(result.failures.single, contains('Missing lib directory'));
  });
}

void _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$contents\n');
}
