import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixtureRoot;
  late Directory repository;
  late Directory fakeBin;
  late File trackedFile;
  late File hook;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync('utexo_pre_commit_');
    repository = Directory('${fixtureRoot.path}/repository')..createSync();
    fakeBin = Directory('${fixtureRoot.path}/bin')..createSync();
    hook = File('${Directory.current.path}/scripts/git-hooks/pre-commit');

    _runGit(repository, const ['init', '--quiet']);
    trackedFile = File('${repository.path}/tracked.txt')
      ..writeAsStringSync('staged\n');
    _runGit(repository, const ['add', 'tracked.txt']);

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
    final chmod = Process.runSync('chmod', ['+x', make.path]);
    if (chmod.exitCode != 0) {
      throw StateError('Could not make the fixture command executable.');
    }
  });

  tearDown(() {
    fixtureRoot.deleteSync(recursive: true);
  });

  test('accepts a worktree that exactly matches the staged snapshot', () {
    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}', contains('Quality gates passed'));
  });

  test('rejects unstaged tracked input before lint', () {
    trackedFile.writeAsStringSync('unstaged\n', mode: FileMode.append);

    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('Unstaged tracked changes'));
  });

  test('rejects untracked non-ignored input before lint', () {
    File('${repository.path}/untracked_test.dart')
        .writeAsStringSync('void main() {}');

    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('Untracked non-ignored files'));
  });

  test('allows ignored local development artifacts', () {
    File('${repository.path}/.gitignore').writeAsStringSync('ignored.local\n');
    _runGit(repository, const ['add', '.gitignore']);
    File('${repository.path}/ignored.local').writeAsStringSync('local only\n');

    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('rejects a tracked worktree mutation made by the gate', () {
    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-worktree',
    );

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('Unstaged tracked changes'));
  });

  test('rejects an untracked input created by the gate', () {
    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-untracked',
    );

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('Untracked non-ignored files'));
  });

  test('rejects a staged-tree mutation made by the gate', () {
    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'mutate-index',
    );

    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('staged tree changed'));
  });

  test('preserves a failing lint command status', () {
    final result = _runHook(
      hook: hook,
      repository: repository,
      fakeBin: fakeBin,
      action: 'fail',
    );

    expect(result.exitCode, 23);
    expect('${result.stdout}', isNot(contains('Quality gates passed')));
  });
}

ProcessResult _runHook({
  required File hook,
  required Directory repository,
  required Directory fakeBin,
  String action = 'pass',
}) {
  return Process.runSync(
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

void _runGit(Directory repository, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: repository.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
