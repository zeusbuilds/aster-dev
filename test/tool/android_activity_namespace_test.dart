import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'the declared launch class exists for ordinary and isolated QA namespaces',
    () {
      final manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
      final activity = manifest
          .findAllElements('activity')
          .single
          .getAttribute('android:name')!;
      final declaration = File(
        'android/app/src/main/kotlin/com/example/asterdev/MainActivity.kt',
      ).readAsStringSync();
      final package = RegExp(
        r'^package ([A-Za-z0-9_.]+)$',
        multiLine: true,
      ).firstMatch(declaration)!.group(1)!;
      final className = RegExp(
        r'^class ([A-Za-z0-9_]+)\s*:',
        multiLine: true,
      ).firstMatch(declaration)!.group(1)!;

      // Android expands a relative manifest name using the variant namespace.
      // A different application identity must still point to the real class.
      for (final namespace in [
        'com.example.asterdev',
        'com.aster.bfa7.c1qa',
        'org.owned.release',
      ]) {
        final resolved = activity.startsWith('.')
            ? '$namespace$activity'
            : activity.contains('.')
            ? activity
            : '$namespace.$activity';
        expect(resolved, '$package.$className', reason: namespace);
        expect(
          File(
            'android/app/src/main/kotlin/${resolved.replaceAll('.', '/')}.kt',
          ).existsSync(),
          isTrue,
          reason: 'The merged launch class must exist for $namespace.',
        );
      }
    },
  );
}
