import 'package:url_launcher/url_launcher.dart';

import '../config/public_https_uri_policy.dart';
import '../errors/errors.dart';

typedef ExternalUriInvoker = Future<bool> Function(Uri uri);

/// Bounded platform boundary for opening public HTTPS resources.
abstract interface class ExternalUriService {
  Future<AppResult<void>> open(Uri uri);
}

/// `url_launcher` adapter kept outside feature presentation code.
final class PlatformExternalUriService implements ExternalUriService {
  PlatformExternalUriService({ExternalUriInvoker? invoker})
    : _invoker = invoker ?? _launch;

  static const maximumUriCharacters = PublicHttpsUriPolicy.maximumCharacters;
  final ExternalUriInvoker _invoker;

  @override
  Future<AppResult<void>> open(Uri uri) async {
    try {
      PublicHttpsUriPolicy.validate(uri);
    } on AppConfigurationException {
      return AppResult.failure(_invalidUriFailure);
    }
    try {
      if (!await _invoker(uri)) {
        return AppResult.failure(_unavailableFailure);
      }
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'external_uri_open_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The link could not be opened.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static const _invalidUriFailure = AppFailure(
    code: 'external_uri_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'This link is not supported.',
    retryable: false,
  );

  static const _unavailableFailure = AppFailure(
    code: 'external_uri_unavailable',
    kind: AppFailureKind.unavailable,
    userMessage: 'No app is available to open this link.',
    retryable: false,
  );

  static Future<bool> _launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
