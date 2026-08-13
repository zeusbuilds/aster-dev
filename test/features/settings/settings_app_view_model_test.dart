import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app state rejects an unavailable in-flight link in release mode', () {
    expect(
      () => SettingsAppState(
        availableLinks: const {},
        openingLink: SettingsExternalLink.contactSupport,
      ),
      throwsArgumentError,
    );
  });

  test(
    'loads metadata and configured link availability independently',
    () async {
      final repository = SettingsAppRepository(
        _QueuedMetadataService([
          Future.value(
            const AppResult.success(
              AppBuildMetadata(version: '1.0.0', buildNumber: '9'),
            ),
          ),
        ]),
        _ControlledExternalUriService(),
      );
      final container = _container(
        repository,
        PublicLinkConfiguration(
          privacyPolicy: Uri.parse('https://wallet.example.com/privacy'),
        ),
      );
      addTearDown(container.dispose);

      final state = await container.read(settingsAppViewModelProvider.future);

      expect(state.metadata?.version, '1.0.0');
      expect(state.metadata?.buildNumber, '9');
      expect(state.isAvailable(SettingsExternalLink.privacyPolicy), isTrue);
      expect(state.isAvailable(SettingsExternalLink.twitter), isFalse);
    },
  );

  test('serializes link launches and retains a typed failure', () async {
    final launch = Completer<AppResult<void>>();
    final externalUris = _ControlledExternalUriService()..next = launch.future;
    final repository = SettingsAppRepository(
      _QueuedMetadataService([
        Future.value(
          const AppResult.success(
            AppBuildMetadata(version: '1.0.0', buildNumber: '1'),
          ),
        ),
      ]),
      externalUris,
    );
    final container = _container(
      repository,
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example.com'),
        termsOfService: Uri.parse('https://wallet.example.com/terms'),
      ),
    );
    addTearDown(container.dispose);
    await container.read(settingsAppViewModelProvider.future);
    final notifier = container.read(settingsAppViewModelProvider.notifier);

    final first = notifier.openLink(SettingsExternalLink.contactSupport);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(settingsAppViewModelProvider).value?.openingLink,
      SettingsExternalLink.contactSupport,
    );
    expect(
      await notifier.openLink(SettingsExternalLink.termsOfService),
      isFalse,
    );
    launch.complete(
      const AppResult.failure(
        AppFailure(
          code: 'browser_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The link could not be opened.',
          retryable: true,
        ),
      ),
    );

    expect(await first, isFalse);
    final failed = container.read(settingsAppViewModelProvider).value!;
    expect(failed.openingLink, isNull);
    expect(failed.operationFailure?.code, 'browser_failed');
    notifier.clearOperationFailure();
    expect(
      container.read(settingsAppViewModelProvider).value?.operationFailure,
      isNull,
    );
    expect(externalUris.opened, [Uri.parse('https://support.example.com')]);
  });

  test('metadata retry and link completion merge into latest state', () async {
    final metadataRetry = Completer<AppResult<AppBuildMetadata>>();
    final linkOpen = Completer<AppResult<void>>();
    final repository = SettingsAppRepository(
      _QueuedMetadataService([
        Future.value(
          const AppResult.failure(
            AppFailure(
              code: 'metadata_unavailable',
              kind: AppFailureKind.unavailable,
              userMessage: 'Version unavailable.',
              retryable: true,
            ),
          ),
        ),
        metadataRetry.future,
      ]),
      _ControlledExternalUriService()..next = linkOpen.future,
    );
    final container = _container(
      repository,
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example.com'),
      ),
    );
    addTearDown(container.dispose);
    await container.read(settingsAppViewModelProvider.future);
    final notifier = container.read(settingsAppViewModelProvider.notifier);

    final retry = notifier.retryMetadata();
    final open = notifier.openLink(SettingsExternalLink.contactSupport);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(settingsAppViewModelProvider).value?.metadataLoading,
      isTrue,
    );
    expect(
      container.read(settingsAppViewModelProvider).value?.openingLink,
      SettingsExternalLink.contactSupport,
    );

    metadataRetry.complete(
      const AppResult.success(
        AppBuildMetadata(version: '2.0.0', buildNumber: '10'),
      ),
    );
    await retry;
    expect(
      container.read(settingsAppViewModelProvider).value?.openingLink,
      SettingsExternalLink.contactSupport,
    );

    linkOpen.complete(const AppResult.success(null));
    expect(await open, isTrue);
    final completed = container.read(settingsAppViewModelProvider).value!;
    expect(completed.metadata?.version, '2.0.0');
    expect(completed.metadataFailure, isNull);
    expect(completed.openingLink, isNull);
  });

  test('malformed link configuration cannot suppress app metadata', () async {
    final repository = SettingsAppRepository(
      _QueuedMetadataService([
        Future.value(
          const AppResult.success(
            AppBuildMetadata(version: '4.0.0', buildNumber: '12'),
          ),
        ),
      ]),
      _ControlledExternalUriService(),
    );
    final container = _container(
      repository,
      PublicLinkConfiguration(
        contactSupport: Uri.parse('http://support.example.com'),
      ),
    );
    addTearDown(container.dispose);

    final state = await container.read(settingsAppViewModelProvider.future);

    expect(state.metadata?.version, '4.0.0');
    expect(state.availableLinks, isEmpty);
    expect(state.linkConfigurationFailure?.kind, AppFailureKind.configuration);
  });

  test('stale metadata retry cannot overwrite a dependency rebuild', () async {
    final staleRetry = Completer<AppResult<AppBuildMetadata>>();
    var repository = SettingsAppRepository(
      _QueuedMetadataService([
        Future.value(
          const AppResult.failure(
            AppFailure(
              code: 'metadata_unavailable',
              kind: AppFailureKind.unavailable,
              userMessage: 'Version unavailable.',
              retryable: true,
            ),
          ),
        ),
        staleRetry.future,
      ]),
      _ControlledExternalUriService(),
    );
    final container = ProviderContainer(
      overrides: [
        settingsAppRepositoryProvider.overrideWith((ref) => repository),
        publicLinkConfigurationProvider.overrideWithValue(
          const PublicLinkConfiguration(),
        ),
      ],
    );
    final subscription = container.listen(
      settingsAppViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await container.read(settingsAppViewModelProvider.future);
    final stale = container
        .read(settingsAppViewModelProvider.notifier)
        .retryMetadata();
    await Future<void>.delayed(Duration.zero);

    repository = SettingsAppRepository(
      _QueuedMetadataService([
        Future.value(
          const AppResult.success(
            AppBuildMetadata(version: '9.0.0', buildNumber: '1'),
          ),
        ),
      ]),
      _ControlledExternalUriService(),
    );
    container.invalidate(settingsAppRepositoryProvider);
    final rebuilt = await container.read(settingsAppViewModelProvider.future);
    expect(rebuilt.metadata?.version, '9.0.0');

    staleRetry.complete(
      const AppResult.success(
        AppBuildMetadata(version: '1.0.0', buildNumber: 'old'),
      ),
    );
    await stale;
    expect(
      container.read(settingsAppViewModelProvider).value?.metadata?.version,
      '9.0.0',
    );
  });
}

ProviderContainer _container(
  SettingsAppRepository repository,
  PublicLinkConfiguration configuration,
) {
  final container = ProviderContainer(
    overrides: [
      settingsAppRepositoryProvider.overrideWithValue(repository),
      publicLinkConfigurationProvider.overrideWithValue(configuration),
    ],
  );
  container.listen(settingsAppViewModelProvider, (_, _) {});
  return container;
}

final class _QueuedMetadataService implements AppMetadataService {
  _QueuedMetadataService(this.responses);

  final List<Future<AppResult<AppBuildMetadata>>> responses;

  @override
  Future<AppResult<AppBuildMetadata>> load() {
    if (responses.isEmpty) throw StateError('No metadata response queued.');
    return responses.removeAt(0);
  }
}

final class _ControlledExternalUriService implements ExternalUriService {
  Future<AppResult<void>>? next;
  final opened = <Uri>[];

  @override
  Future<AppResult<void>> open(Uri uri) {
    opened.add(uri);
    return next ?? Future.value(const AppResult.success(null));
  }
}
