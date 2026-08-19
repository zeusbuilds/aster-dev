import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_repository_governance.dart';

void main() {
  test('current repository governance contract passes', () {
    expect(verifyRepositoryGovernance(Directory.current), isEmpty);
  });

  test('rejects an unpinned third-party action', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final workflow = File('${repository.path}/.github/workflows/dart.yml');
    workflow.writeAsStringSync(
      workflow.readAsStringSync().replaceFirst(
        'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
        'actions/checkout@main',
      ),
    );

    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('unpinned action')),
    );
  });

  test('rejects missing ecosystem ownership', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final dependabot = File('${repository.path}/.github/dependabot.yml');
    dependabot.writeAsStringSync(
      dependabot.readAsStringSync().replaceFirst(
        'package-ecosystem: bundler',
        'package-ecosystem: pub',
      ),
    );

    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('every owned package ecosystem')),
    );
  });

  test('rejects malformed workflow structure and unbounded jobs', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final workflow = File('${repository.path}/.github/workflows/platform.yml');
    workflow.writeAsStringSync(
      workflow.readAsStringSync().replaceFirst('    timeout-minutes: 45\n', ''),
    );

    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('must have a 1...120 minute timeout')),
    );

    workflow.writeAsStringSync('jobs: [unterminated');
    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('not valid workflow YAML')),
    );
  });

  test('rejects alternate workflows and job permission escalation', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    File('${repository.path}/.github/workflows/unreviewed.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: Unreviewed\non: push\njobs: {}\n');

    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('exactly dart.yml and platform.yml')),
    );

    File('${repository.path}/.github/workflows/unreviewed.yaml').deleteSync();
    final platform = File('${repository.path}/.github/workflows/platform.yml');
    platform.writeAsStringSync(
      platform.readAsStringSync().replaceFirst(
        '    timeout-minutes: 45\n',
        '    timeout-minutes: 45\n'
            '    permissions:\n'
            '      contents: write\n',
      ),
    );

    expect(
      verifyRepositoryGovernance(repository),
      contains(contains('must not override workflow permissions')),
    );
  });

  test('rejects compact secret expressions and pull request target', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final quality = File('${repository.path}/.github/workflows/dart.yml');
    quality.writeAsStringSync(
      quality
          .readAsStringSync()
          .replaceFirst('  pull_request:\n', '  pull_request_target:\n')
          .replaceFirst(
            '        run: flutter pub get --enforce-lockfile',
            '        env:\n'
                '          TOKEN: \${{secrets.RELEASE_TOKEN}}\n'
                '        run: flutter pub get --enforce-lockfile',
          ),
    );

    final failures = verifyRepositoryGovernance(repository);
    expect(failures, contains(contains('must not consume repository secrets')));
    expect(failures, contains(contains('must not use pull_request_target')));
  });

  test('rejects effective ownership overrides and commented commands', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final codeowners = File('${repository.path}/.github/CODEOWNERS');
    codeowners.writeAsStringSync(
      '${codeowners.readAsStringSync()}\n/android/ @unreviewed\n',
    );
    final quality = File('${repository.path}/.github/workflows/dart.yml');
    quality.writeAsStringSync(
      quality.readAsStringSync().replaceFirst(
        '        run: dart run tool/verify_repository_governance.dart',
        '        # dart run tool/verify_repository_governance.dart\n'
            '        run: echo skipped',
      ),
    );

    final failures = verifyRepositoryGovernance(repository);
    expect(failures, contains(contains('reviewed ownership order')));
    expect(
      failures,
      contains(contains('Quality workflow is missing: dart run tool/verify')),
    );
  });

  test('rejects Dependabot directory drift and bracketed secrets', () {
    final repository = Directory.systemTemp.createTempSync('aster-governance-');
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyGovernanceFiles(repository);
    final dependabot = File('${repository.path}/.github/dependabot.yml');
    dependabot.writeAsStringSync(
      dependabot.readAsStringSync().replaceFirst(
        '    directory: /android',
        '    directory: /',
      ),
    );
    final quality = File('${repository.path}/.github/workflows/dart.yml');
    quality.writeAsStringSync(
      quality.readAsStringSync().replaceFirst(
        '        run: flutter pub get --enforce-lockfile',
        '        env:\n'
            "          TOKEN: \${{ secrets['RELEASE_TOKEN'] }}\n"
            '        run: flutter pub get --enforce-lockfile',
      ),
    );

    final failures = verifyRepositoryGovernance(repository);
    expect(failures, contains(contains('gradle ownership')));
    expect(failures, contains(contains('must not consume repository secrets')));
  });

  group('Android post-test cleanup', () {
    const hostTests = '''
      - name: Run Android host tests
        working-directory: android
        run: ./gradlew :app:testDebugUnitTest --no-daemon
''';
    const cleanup = '''
      - name: Release transient Android build outputs
        if: always()
        run: flutter clean
''';

    test('rejects a missing cleanup', () {
      _expectInvalidAndroidCleanup(
        addTearDown,
        (source) => source.replaceFirst(cleanup, ''),
      );
    });

    test('rejects cleanup that is conditional on success', () {
      _expectInvalidAndroidCleanup(
        addTearDown,
        (source) => source.replaceFirst(
          '        if: always()\n',
          '        if: success()\n',
        ),
      );
    });

    test('rejects cleanup scoped to the Android directory', () {
      _expectInvalidAndroidCleanup(
        addTearDown,
        (source) => source.replaceFirst(
          '        if: always()\n        run: flutter clean\n',
          '        if: always()\n'
              '        working-directory: android\n'
              '        run: flutter clean\n',
        ),
      );
    });

    test('rejects cleanup before host tests', () {
      _expectInvalidAndroidCleanup(
        addTearDown,
        (source) =>
            source.replaceFirst('$hostTests\n$cleanup', '$cleanup\n$hostTests'),
      );
    });
  });
}

void _expectInvalidAndroidCleanup(
  void Function(FutureOr<void> Function()) registerTearDown,
  String Function(String) mutate,
) {
  final repository = Directory.systemTemp.createTempSync('aster-governance-');
  registerTearDown(() => repository.deleteSync(recursive: true));
  _copyGovernanceFiles(repository);
  final platform = File('${repository.path}/.github/workflows/platform.yml');
  platform.writeAsStringSync(mutate(platform.readAsStringSync()));

  expect(
    verifyRepositoryGovernance(repository),
    contains(contains('always clean transient build outputs after host tests')),
  );
}

void _copyGovernanceFiles(Directory target) {
  for (final relative in const [
    '.github/CODEOWNERS',
    '.github/dependabot.yml',
    '.github/pull_request_template.md',
    '.github/workflows/dart.yml',
    '.github/workflows/platform.yml',
  ]) {
    final destination = File('${target.path}/$relative')
      ..createSync(recursive: true);
    destination.writeAsBytesSync(File(relative).readAsBytesSync());
  }
}
