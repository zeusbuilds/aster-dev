import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import 'public_https_uri_policy.dart';

/// How this build is permitted to access CoinGecko-backed market data.
enum MarketDataAccess {
  /// No release-approved market service was configured.
  unavailable,

  /// CoinGecko's keyless public pool, permitted only outside release builds.
  developmentKeyless,

  /// A deployment-owned HTTPS proxy with an approved provider contract.
  deploymentProxy,
}

/// Validated, non-secret market-data endpoint configuration.
///
/// Mobile clients cannot protect a third-party API secret. Release builds must
/// therefore use a deployment-owned proxy and never embed a CoinGecko key.
@immutable
final class MarketDataConfiguration {
  const MarketDataConfiguration._({required this.access, this.baseUri});

  /// Resolves compile-time configuration for the current build mode.
  factory MarketDataConfiguration.fromEnvironment() {
    return MarketDataConfiguration.resolve(
      configuredBase: const String.fromEnvironment('UTEXO_MARKET_API_BASE_URL'),
      releaseMode: kReleaseMode,
    );
  }

  /// Resolves a deployment value under an explicit build-mode policy.
  ///
  /// This public pure constructor exists so release-mode behavior can be
  /// proven in host tests without compiling a second application binary.
  factory MarketDataConfiguration.resolve({
    required String configuredBase,
    required bool releaseMode,
  }) {
    if (configuredBase.isEmpty) {
      return releaseMode
          ? const MarketDataConfiguration._(
              access: MarketDataAccess.unavailable,
            )
          : MarketDataConfiguration.developmentKeyless();
    }
    final baseUri = _parseDeploymentBase(configuredBase);
    return MarketDataConfiguration._(
      access: MarketDataAccess.deploymentProxy,
      baseUri: baseUri,
    );
  }

  /// Creates the keyless configuration used by deterministic tests and local
  /// non-release development only.
  factory MarketDataConfiguration.developmentKeyless() {
    return MarketDataConfiguration._(
      access: MarketDataAccess.developmentKeyless,
      baseUri: Uri.parse('https://api.coingecko.com/api/v3/'),
    );
  }

  /// Access policy selected for this build.
  final MarketDataAccess access;

  /// Validated endpoint root, or `null` when release access is unavailable.
  final Uri? baseUri;

  /// Builds one fixed provider-compatible endpoint below [baseUri].
  Uri endpoint(String relativePath) {
    final base = baseUri;
    if (base == null) throw const AppConfigurationException();
    if (relativePath.isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.contains('..') ||
        !RegExp(r'^[a-z0-9_/-]+$').hasMatch(relativePath)) {
      throw const AppConfigurationException();
    }
    return base.resolve(relativePath);
  }
}

Uri _parseDeploymentBase(String raw) {
  if (RegExp(r'%(?:2e|2f|5c)', caseSensitive: false).hasMatch(raw)) {
    throw const AppConfigurationException();
  }
  final parsed = PublicHttpsUriPolicy.parse(raw);
  final host = parsed.host.toLowerCase();
  if (host == 'api.coingecko.com' || host == 'pro-api.coingecko.com') {
    throw const AppConfigurationException();
  }
  if (parsed.pathSegments.any(
    (segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\'),
  )) {
    throw const AppConfigurationException();
  }
  final path = parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/';
  return parsed.replace(path: path);
}
