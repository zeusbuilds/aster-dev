import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../errors/errors.dart';

/// Bounded, app-owned subset of package metadata safe for presentation.
@immutable
final class AppBuildMetadata {
  const AppBuildMetadata({required this.version, required this.buildNumber});

  static const maximumFieldCharacters = 64;

  /// User-facing release version, such as `1.0.0`.
  final String version;

  /// Platform build identifier, such as an Android version code.
  final String buildNumber;

  /// Whether both values are bounded and safe to display.
  bool get isValid {
    return _isValidField(version, allowEmpty: false) &&
        _isValidField(buildNumber, allowEmpty: true);
  }

  @override
  bool operator ==(Object other) =>
      other is AppBuildMetadata &&
      other.version == version &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(version, buildNumber);
}

/// Injectable package-metadata loader used by the platform adapter.
typedef AppMetadataLoader = Future<AppBuildMetadata> Function();

/// Platform boundary for retrieving the installed application's metadata.
abstract interface class AppMetadataService {
  Future<AppResult<AppBuildMetadata>> load();
}

/// `package_info_plus` adapter kept outside feature and presentation code.
final class PlatformAppMetadataService implements AppMetadataService {
  PlatformAppMetadataService({AppMetadataLoader? loader})
    : _loader = loader ?? _loadFromPlatform;

  final AppMetadataLoader _loader;

  @override
  Future<AppResult<AppBuildMetadata>> load() async {
    try {
      final metadata = await _loader();
      if (!metadata.isValid) {
        return AppResult.failure(_invalidMetadataFailure);
      }
      return AppResult.success(metadata);
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'app_metadata_load_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The app version could not be loaded.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static Future<AppBuildMetadata> _loadFromPlatform() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppBuildMetadata(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  }

  static const _invalidMetadataFailure = AppFailure(
    code: 'app_metadata_invalid',
    kind: AppFailureKind.configuration,
    userMessage: 'The app version is unavailable in this build.',
    retryable: false,
  );
}

bool _isValidField(String value, {required bool allowEmpty}) {
  if (value.isEmpty) return allowEmpty;
  return value == value.trim() &&
      value.length <= AppBuildMetadata.maximumFieldCharacters &&
      _packageMetadataField.hasMatch(value);
}

final _packageMetadataField = RegExp(r'^[0-9A-Za-z][0-9A-Za-z._+\-]*$');
