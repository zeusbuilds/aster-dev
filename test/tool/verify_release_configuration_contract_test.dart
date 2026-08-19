import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_release_configuration_contract.dart';

void main() {
  test('current release configuration contract passes', () {
    expect(verifyReleaseConfigurationContract(Directory.current), isEmpty);
  });

  test('rejects a release build that drops the manifest', () {
    final repository = Directory.systemTemp.createTempSync(
      'aster-release-contract-',
    );
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyContractFiles(repository);
    final makefile = File('${repository.path}/Makefile');
    makefile.writeAsStringSync(
      makefile.readAsStringSync().replaceFirst(
        '--dart-define-from-file="\$(RELEASE_CONFIG)"',
        '--dart-define=ASTER_NETWORK=mainnet',
      ),
    );

    expect(
      verifyReleaseConfigurationContract(repository),
      contains(contains('four release artifact builds')),
    );
  });

  test('rejects runtime key drift', () {
    final repository = Directory.systemTemp.createTempSync(
      'aster-release-contract-',
    );
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyContractFiles(repository);
    final environment = File(
      '${repository.path}/lib/core/config/app_environment.dart',
    );
    environment.writeAsStringSync(
      environment.readAsStringSync().replaceAll(
        'ASTER_VSS_URL',
        'ASTER_VAULT_URL',
      ),
    );

    expect(
      verifyReleaseConfigurationContract(repository),
      contains(contains('Runtime release keys differ')),
    );
  });

  test('does not accept a release key mentioned only in a comment', () {
    final repository = Directory.systemTemp.createTempSync(
      'aster-release-contract-',
    );
    addTearDown(() => repository.deleteSync(recursive: true));
    _copyContractFiles(repository);
    final market = File(
      '${repository.path}/lib/core/config/market_data_configuration.dart',
    );
    market.writeAsStringSync(
      market.readAsStringSync().replaceFirst(
        "const String.fromEnvironment('ASTER_MARKET_API_BASE_URL')",
        "const String.fromEnvironment('UNREVIEWED_MARKET_URL') "
            '// ASTER_MARKET_API_BASE_URL',
      ),
    );

    expect(
      verifyReleaseConfigurationContract(repository),
      contains(contains('Runtime release keys differ')),
    );
  });
}

void _copyContractFiles(Directory target) {
  for (final relative in const [
    '.gitignore',
    'Makefile',
    'config/README.md',
    'config/release.example.json',
    'lib/core/config/app_environment.dart',
    'lib/core/config/market_data_configuration.dart',
    'lib/core/config/public_link_configuration.dart',
  ]) {
    final destination = File('${target.path}/$relative')
      ..createSync(recursive: true);
    destination.writeAsBytesSync(File(relative).readAsBytesSync());
  }
}
