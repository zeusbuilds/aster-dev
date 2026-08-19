import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory fixtureRoot;
  late Directory repository;
  late Directory fakeBin;
  late File trackedFile;
  late File hook;

  setUp(() async {
    fixtureRoot = Directory.systemTemp.createTempSync('aster_pre_commit_');
    repository = Directory('${fixtureRoot.path}/repository')..createSync();
    fakeBin = Directory('${fixtureRoot.path}/bin')..createSync();
    for (final relativePath in <String>[
      'scripts/git-hooks/pre-commit',
      'scripts/bounded-command.sh',
      'tool/run_bounded_command.dart',
      'tool/bounded_process.dart',
    ]) {
      final target = File('${repository.path}/$relativePath');
      target.parent.createSync(recursive: true);
      File('${Directory.current.path}/$relativePath').copySync(target.path);
    }
    linkTestDartRuntime(repository);
    hook = File('${repository.path}/scripts/git-hooks/pre-commit');
    await makeTestExecutable(hook);

    await _runGit(repository, const ['init', '--quiet']);
    trackedFile = File('${repository.path}/tracked.txt')
      ..writeAsStringSync('staged\n');
    await _runGit(repository, const ['add', '.']);

    final make = File('${fakeBin.path}/make')
      ..writeAsStringSync(r'''#!/bin/sh
set -eu
[ "$#" -eq 1 ] && [ "$1" = "lint" ] || exit 96
case "${HOOK_TEST_ACTION:-pass}" in
  pass)
    ;;
  fail)
    exit 23
    ;;
  mutate-worktree)
    printf 'changed\n' >> tracked.txt
    ;;
  mutate-untracked)
    printf 'created during gate\n' > generated-test-input.txt
    ;;
  mutate-index)
    printf 'staged during gate\n' > index-only.txt
    git add index-only.txt
    ;;
  *)
    exit 97
    ;;
esac
''');
    await makeTestExecutable(make);
  });

  tearDown(() {
    fixtureRoot.deleteSync(recursive: true);
  });

  test('accepts a worktree that exactly matches the staged snapshot', () async {
    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Quality gates passed'));
  });

  test('rejects unstaged tracked input before lint', () async {
    trackedFile.writeAsStringSync('unstaged\n', mode: FileMode.append);

    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Unstaged tracked changes'));
  });

  test('rejects untracked non-ignored input before lint', () async {
    File('${repository.path}/untracked_test.dart')
        .writeAsStringSync('void main() {}');

    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Untracked non-ignored files'));
  });

  test('allows ignored local development artifacts', () async {
    File('${repository.path}/.gitignore').writeAsStringSync('ignored.local\n');
    await _runGit(repository, const ['add', '.gitignore']);
    File('${repository.path}/ignored.local').writeAsStringSync('local only\n');

    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects a tracked worktree mutation made by the gate', () async {
    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-worktree',
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Unstaged tracked changes'));
  });

  test('rejects an untracked input created by the gate', () async {
    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-untracked',
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Untracked non-ignored files'));
  });

  test('rejects a staged-tree mutation made by the gate', () async {
    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-index',
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('staged tree changed'));
  });

  test('preserves a failing lint command status', () async {
    final result = await _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'fail',
    );

    expect(result.exitCode, 23);
    expect(result.stdout, isNot(contains('Quality gates passed')));
  });
}

Future<BoundedProcessResult> _runHook({
  required File hook,
  required Directory repository,
  required Directory fakeBin,
  String action = 'pass',
}) {
  return runTestProcess(
    hook.path,
    const [],
    workingDirectory: repository.path,
    environment: {
      ...Platform.environment,
      'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      'HOOK_TEST_ACTION': action,
    },
  );
}

Future<void> _runGit(Directory repository, List<String> arguments) async {
  final result = await runTestProcess(
    'git',
    arguments,
    workingDirectory: repository.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
