import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads app-owned package metadata through the platform boundary',
    () async {
      final metadata = _MetadataService(
        const AppResult.success(
          AppBuildMetadata(version: '1.2.3', buildNumber: '7'),
        ),
      );
      final repository = SettingsAppRepository(metadata, _ExternalUriService());

      final result = await repository.loadMetadata();

      expect((result as AppSuccess<AppBuildMetadata>).value.version, '1.2.3');
      expect(metadata.calls, 1);
    },
  );

  test('exposes and opens only explicitly configured public links', () async {
    final support = Uri.parse('https://support.example.com/help');
    final privacy = Uri.parse('https://wallet.example.com/legal/privacy');
    final externalUris = _ExternalUriService();
    final configuration = PublicLinkConfiguration(
      contactSupport: support,
      privacyPolicy: privacy,
    );
    final repository = SettingsAppRepository(
      _MetadataService(
        const AppResult.success(
          AppBuildMetadata(version: '1.0.0', buildNumber: '1'),
        ),
      ),
      externalUris,
    );

    expect(repository.availableLinks(configuration), {
      SettingsExternalLink.contactSupport,
      SettingsExternalLink.privacyPolicy,
    });
    expect(
      await repository.openLink(
        SettingsExternalLink.contactSupport,
        configuration,
      ),
      isA<AppSuccess<void>>(),
    );
    expect(externalUris.opened, [support]);

    final unavailable = await repository.openLink(
      SettingsExternalLink.telegram,
      configuration,
    );
    expect(
      (unavailable as AppFailureResult<void>).failure.code,
      'settings_link_unavailable',
    );
    expect(externalUris.opened, [support]);
  });

  test('rejects invalid explicitly constructed link configuration', () {
    final invalid = PublicLinkConfiguration(
      contactSupport: Uri.parse('http://support.example.com'),
    );

    expect(
      () => SettingsAppRepository(
        _MetadataService(
          const AppResult.success(
            AppBuildMetadata(version: '1.0.0', buildNumber: '1'),
          ),
        ),
        _ExternalUriService(),
      ).availableLinks(invalid),
      throwsA(isA<AppConfigurationException>()),
    );
  });
}

final class _MetadataService implements AppMetadataService {
  _MetadataService(this.result);

  final AppResult<AppBuildMetadata> result;
  int calls = 0;

  @override
  Future<AppResult<AppBuildMetadata>> load() async {
    calls++;
    return result;
  }
}

final class _ExternalUriService implements ExternalUriService {
  final opened = <Uri>[];

  @override
  Future<AppResult<void>> open(Uri uri) async {
    opened.add(uri);
    return const AppResult.success(null);
  }
}
