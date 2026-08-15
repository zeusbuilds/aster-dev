import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../data/repository/repository.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'settings_app_view_model.g.dart';

/// Owns package metadata loading and serialized public-link launches.
@riverpod
class SettingsAppViewModel extends _$SettingsAppViewModel {
  var _stateGeneration = 0;

  @override
  Future<SettingsAppState> build() async {
    _stateGeneration += 1;
    final repository = ref.watch(settingsAppRepositoryProvider);
    final links = _resolveLinks(repository);
    return _load(repository, links);
  }

  /// Retries package metadata without disabling independently configured links.
  Future<void> retryMetadata() async {
    final current = state.value;
    if (current == null ||
        current.metadataLoading ||
        current.metadataFailure?.retryable != true) {
      return;
    }
    final generation = _stateGeneration;
    state = AsyncData(current.beginMetadataLoad());
    final repository = ref.read(settingsAppRepositoryProvider);
    final result = await _guardMetadata(repository);
    if (!ref.mounted || generation != _stateGeneration) return;
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(_applyMetadataResult(latest, result));
  }

  /// Opens one configured public destination and suppresses overlapping opens.
  Future<bool> openLink(SettingsExternalLink link) async {
    final current = state.value;
    if (current == null ||
        current.openingLink != null ||
        !current.isAvailable(link)) {
      return false;
    }
    final generation = _stateGeneration;
    state = AsyncData(current.beginOpening(link));
    final repository = ref.read(settingsAppRepositoryProvider);
    final result = await _guardOpen(repository, link);
    if (!ref.mounted || generation != _stateGeneration) return false;
    final latest = state.value;
    if (latest == null || latest.openingLink != link) return false;
    return switch (result) {
      AppSuccess<void>() => () {
        state = AsyncData(latest.completeOpening());
        return true;
      }(),
      AppFailureResult<void>(:final failure) => () {
        state = AsyncData(latest.completeOpening(failure: failure));
        return false;
      }(),
    };
  }

  /// Clears a link-launch failure after it has been presented once.
  void clearOperationFailure() {
    final current = state.value;
    if (current == null || current.operationFailure == null) return;
    state = AsyncData(current.clearOperationFailure());
  }

  Future<SettingsAppState> _load(
    SettingsAppRepository repository,
    ({Set<SettingsExternalLink> values, AppFailure? failure}) links,
  ) async {
    final result = await _guardMetadata(repository);
    final initial = SettingsAppState(
      availableLinks: links.values,
      linkConfigurationFailure: links.failure,
    );
    return _applyMetadataResult(initial, result);
  }

  ({Set<SettingsExternalLink> values, AppFailure? failure}) _resolveLinks(
    SettingsAppRepository repository,
  ) {
    try {
      final configuration = ref.watch(publicLinkConfigurationProvider);
      return (values: repository.availableLinks(configuration), failure: null);
    } catch (error, stackTrace) {
      return (
        values: const <SettingsExternalLink>{},
        failure: AppFailure(
          code: 'settings_link_configuration_invalid',
          kind: AppFailureKind.configuration,
          userMessage: 'Public links are unavailable in this build.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<AppResult<AppBuildMetadata>> _guardMetadata(
    SettingsAppRepository repository,
  ) async {
    try {
      return await repository.loadMetadata();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<void>> _guardOpen(
    SettingsAppRepository repository,
    SettingsExternalLink link,
  ) async {
    try {
      final configuration = ref.read(publicLinkConfigurationProvider);
      return await repository.openLink(link, configuration);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  SettingsAppState _applyMetadataResult(
    SettingsAppState current,
    AppResult<AppBuildMetadata> result,
  ) {
    return switch (result) {
      AppSuccess<AppBuildMetadata>(:final value) => current.completeMetadata(
        value,
      ),
      AppFailureResult<AppBuildMetadata>(:final failure) =>
        current.failMetadata(failure),
    };
  }
}
