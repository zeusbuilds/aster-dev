import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_barrel_exports.dart';

void main() {
  late Directory repository;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_barrels_');
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts sorted acyclic boundary barrels and multiline exports', () {
    _write(repository, 'lib/models/amount.dart', 'class Amount {}');
    _write(repository, 'lib/models/payment.dart', 'class Payment {}');
    _write(
      repository,
      'lib/models/models.dart',
      "export\n    'amount.dart';\nexport 'payment.dart';",
    );
    _write(
      repository,
      'lib/domain/domain.dart',
      "export '../models/models.dart';",
    );

    final result = verifyBarrelExports(repository);

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.sourceCount, 4);
    expect(result.barrelCount, 2);
  });

  test('reports naming ordering duplicate and target violations', () {
    _write(repository, 'lib/models/a.dart', 'class A {}');
    _write(repository, 'lib/models/_private.dart', 'class Private {}');
    _write(repository, 'lib/models/generated.g.dart', 'class Generated {}');
    _write(
      repository,
      'lib/models/wrong.dart',
      "export 'missing.dart';\n"
          "export 'generated.g.dart';\n"
          "export '_private.dart';\n"
          "export 'a.dart';\n"
          "export 'a.dart';\n"
          "export 'package:http/http.dart';\n"
          "export '../../outside.dart';",
    );
    _write(repository, 'outside.dart', 'class Outside {}');

    final result = verifyBarrelExports(repository);

    expect(result.passed, isFalse);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('barrel must be named models.dart'),
        contains('exports must be sorted'),
        contains('duplicate export'),
        contains('missing Dart export missing.dart'),
        contains('generated or private source'),
        contains('only relative repository sources'),
        contains('escapes the lib boundary'),
      ]),
    );
  });

  test(
    'rejects conditional exports, self imports, cycles, and parse errors',
    () {
      _write(repository, 'lib/a/value.dart', 'class Value {}');
      _write(
        repository,
        'lib/a/a.dart',
        "export '../b/b.dart';\n"
            "export 'value.dart' if (dart.library.io) '../b/b.dart';",
      );
      _write(repository, 'lib/a/consumer.dart', "import 'a.dart';");
      _write(repository, 'lib/b/b.dart', "export '../a/a.dart';");
      _write(repository, 'lib/broken.dart', "export 'unterminated.dart;");

      final result = verifyBarrelExports(repository);

      expect(result.passed, isFalse);
      expect(
        result.failures,
        containsAll(<Matcher>[
          contains('conditional barrel exports are prohibited'),
          contains('must not import its own directory barrel'),
          contains('Barrel export cycle'),
          contains('parse error:'),
        ]),
      );
    },
  );

  test('fails closed when the repository has no lib directory', () {
    final result = verifyBarrelExports(repository);

    expect(result.passed, isFalse);
    expect(result.sourceCount, 0);
    expect(result.barrelCount, 0);
    expect(result.failures.single, contains('Missing lib directory'));
  });
}

void _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$contents\n');
}
