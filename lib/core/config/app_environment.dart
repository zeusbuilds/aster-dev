import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import '../validation/validation.dart';

/// Bitcoin chain environment, independent from asset and payment rail.
enum BlockchainEnvironment {
  mainnet,
  signet,
  regtest;

  static BlockchainEnvironment parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'mainnet' || 'bitcoin' => BlockchainEnvironment.mainnet,
      'signet' || 'utexo' => BlockchainEnvironment.signet,
      'regtest' => BlockchainEnvironment.regtest,
      _ => throw const AppConfigurationException(),
    };
  }
}

/// Deployment-owned identity for one RGB fungible asset.
///
/// Contract identity and precision are release configuration, not values that
/// may be inferred from a ticker returned by a wallet or entered by a user.
@immutable
final class RgbAssetConfiguration {
  const RgbAssetConfiguration({
    required this.contractId,
    required this.precision,
  });

  final String contractId;

  /// Decimal precision used to format integer asset-smallest units.
  final int precision;

  @override
  bool operator ==(Object other) =>
      other is RgbAssetConfiguration &&
      other.contractId == contractId &&
      other.precision == precision;

  @override
  int get hashCode => Object.hash(contractId, precision);

  void validate() {
    if (!ProtocolTextPolicy.isVisibleAscii(
      contractId,
      maximumCharacters: 512,
    )) {
      throw const AppConfigurationException();
    }
    if (precision < 0 || precision > 18) {
      throw const AppConfigurationException();
    }
  }
}

/// Public, non-secret service configuration supplied to the wallet runtime.
@immutable
final class WalletServiceConfiguration {
  const WalletServiceConfiguration({
    required this.environment,
    required this.sdkNetwork,
    this.indexerUrl,
    this.rgbTransportProxy,
    this.lspBaseUrl,
    this.vssUrl,
    this.explorerBaseUrl,
    this.usdtAsset,
  });

  /// Reads compile-time configuration without embedding credentials.
  ///
  /// Regtest is deliberately the default so an unconfigured build cannot
  /// become a funds-bearing mainnet wallet by accident.
  factory WalletServiceConfiguration.fromEnvironment() {
    const networkValue = String.fromEnvironment(
      'UTEXO_NETWORK',
      defaultValue: 'regtest',
    );
    if (networkValue != networkValue.trim()) {
      throw const AppConfigurationException();
    }
    final environment = BlockchainEnvironment.parse(networkValue);
    return WalletServiceConfiguration(
      environment: environment,
      sdkNetwork: environment == BlockchainEnvironment.signet
          ? 'utexo'
          : environment.name,
      indexerUrl: _optionalEnvironment('UTEXO_INDEXER_URL'),
      rgbTransportProxy: _optionalEnvironment('UTEXO_RGB_PROXY_URL'),
      lspBaseUrl: _optionalEnvironment('UTEXO_LSP_URL'),
      vssUrl: _optionalEnvironment('UTEXO_VSS_URL'),
      explorerBaseUrl:
          _optionalEnvironment('UTEXO_EXPLORER_URL') ??
          switch (environment) {
            BlockchainEnvironment.mainnet => 'https://mempool.space',
            BlockchainEnvironment.signet => 'https://mempool.space/signet',
            BlockchainEnvironment.regtest => null,
          },
      usdtAsset: _rgbAssetEnvironment(
        contractId: const String.fromEnvironment('UTEXO_USDT_ASSET_ID'),
        precision: const int.fromEnvironment(
          'UTEXO_USDT_PRECISION',
          defaultValue: -1,
        ),
      ),
    );
  }

  final BlockchainEnvironment environment;

  /// Stable SDK network carrier. UTEXO-hosted signet uses the SDK's `utexo`
  /// service profile while the product-facing chain remains signet.
  final String sdkNetwork;
  final String? indexerUrl;
  final String? rgbTransportProxy;
  final String? lspBaseUrl;
  final String? vssUrl;
  final String? explorerBaseUrl;

  /// RGB USDT identity for this exact blockchain environment.
  ///
  /// `null` means the deployment has not configured USDT. Callers must expose
  /// that route as unavailable rather than substituting a ticker-derived ID.
  final RgbAssetConfiguration? usdtAsset;

  @override
  bool operator ==(Object other) =>
      other is WalletServiceConfiguration &&
      other.environment == environment &&
      other.sdkNetwork == sdkNetwork &&
      other.indexerUrl == indexerUrl &&
      other.rgbTransportProxy == rgbTransportProxy &&
      other.lspBaseUrl == lspBaseUrl &&
      other.vssUrl == vssUrl &&
      other.explorerBaseUrl == explorerBaseUrl &&
      other.usdtAsset == usdtAsset;

  @override
  int get hashCode => Object.hash(
    environment,
    sdkNetwork,
    indexerUrl,
    rgbTransportProxy,
    lspBaseUrl,
    vssUrl,
    explorerBaseUrl,
    usdtAsset,
  );

  /// Whether the validated VSS endpoint is an HTTP development endpoint.
  ///
  /// The SDK defaults to rejecting HTTP VSS. This opt-in is derived only after
  /// the app's regtest/loopback policy has accepted the endpoint.
  bool get allowsInsecureLocalVss {
    final value = vssUrl;
    if (value == null || environment != BlockchainEnvironment.regtest) {
      return false;
    }
    final uri = Uri.parse(value);
    return uri.scheme.toLowerCase() == 'http' &&
        (_isLoopback(uri.host) || uri.host == '10.0.2.2');
  }

  /// Validates URL policy before any native wallet is created.
  void validate() {
    final expectedSdkNetwork = environment == BlockchainEnvironment.signet
        ? 'utexo'
        : environment.name;
    if (sdkNetwork != expectedSdkNetwork) {
      throw const AppConfigurationException();
    }
    _validateEndpoint(indexerUrl, _EndpointKind.indexer, environment);
    _validateEndpoint(
      rgbTransportProxy,
      _EndpointKind.rgbTransport,
      environment,
    );
    _validateEndpoint(lspBaseUrl, _EndpointKind.webService, environment);
    _validateEndpoint(vssUrl, _EndpointKind.webService, environment);
    _validateEndpoint(explorerBaseUrl, _EndpointKind.explorer, environment);
    usdtAsset?.validate();
  }

  /// Returns a public explorer URL only for a canonical Bitcoin transaction
  /// ID and a deployment with a validated explorer base.
  Uri? transactionExplorerUri(String txid) {
    final rawBase = explorerBaseUrl;
    if (rawBase == null || !_transactionId.hasMatch(txid)) return null;
    final base = Uri.parse(rawBase);
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'tx',
        txid.toLowerCase(),
      ],
    );
  }

  static void _validateEndpoint(
    String? raw,
    _EndpointKind kind,
    BlockchainEnvironment environment,
  ) {
    if (raw == null) return;
    if (raw != raw.trim() || raw.isEmpty || raw.contains(RegExp(r'\s'))) {
      throw const AppConfigurationException();
    }
    final hasExplicitScheme = raw.contains('://');
    if (!hasExplicitScheme && kind != _EndpointKind.indexer) {
      throw const AppConfigurationException();
    }
    final uri = Uri.tryParse(hasExplicitScheme ? raw : 'tcp://$raw');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const AppConfigurationException();
    }
    final developmentHost =
        environment == BlockchainEnvironment.regtest &&
        (_isLoopback(uri.host) || uri.host == '10.0.2.2');
    if (developmentHost &&
        uri.hasPort &&
        _protectedDevelopmentPorts.contains(uri.port)) {
      throw const AppConfigurationException();
    }
    final allowed = switch (kind) {
      _EndpointKind.indexer =>
        developmentHost
            ? const {'http', 'https', 'tcp', 'ssl'}
            : const {'https', 'ssl'},
      _EndpointKind.rgbTransport =>
        developmentHost
            ? const {'http', 'https', 'rpc', 'rpcs'}
            : const {'https', 'rpcs'},
      _EndpointKind.webService =>
        developmentHost ? const {'http', 'https'} : const {'https'},
      _EndpointKind.explorer => const {'https'},
    };
    if (!allowed.contains(uri.scheme.toLowerCase())) {
      throw const AppConfigurationException();
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      throw const AppConfigurationException();
    }
    if (const {'tcp', 'ssl'}.contains(uri.scheme.toLowerCase()) &&
        !uri.hasPort) {
      throw const AppConfigurationException();
    }
  }

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  /// Ports owned by the unrelated `rgb-lightning-node-perf-lab` project.
  static const _protectedDevelopmentPorts = {18443, 50001, 3000};
}

enum _EndpointKind { indexer, rgbTransport, webService, explorer }

String? _optionalEnvironment(String name) {
  final value = switch (name) {
    'UTEXO_INDEXER_URL' => const String.fromEnvironment('UTEXO_INDEXER_URL'),
    'UTEXO_RGB_PROXY_URL' => const String.fromEnvironment(
      'UTEXO_RGB_PROXY_URL',
    ),
    'UTEXO_LSP_URL' => const String.fromEnvironment('UTEXO_LSP_URL'),
    'UTEXO_VSS_URL' => const String.fromEnvironment('UTEXO_VSS_URL'),
    'UTEXO_EXPLORER_URL' => const String.fromEnvironment('UTEXO_EXPLORER_URL'),
    _ => '',
  };
  return value.isEmpty ? null : value;
}

final _transactionId = RegExp(r'^[0-9a-fA-F]{64}$');

RgbAssetConfiguration? _rgbAssetEnvironment({
  required String contractId,
  required int precision,
}) {
  final hasContractId = contractId.isNotEmpty;
  final hasPrecision = precision >= 0;
  if (!hasContractId && !hasPrecision) return null;
  if (!hasContractId || !hasPrecision) {
    throw const AppConfigurationException();
  }
  return RgbAssetConfiguration(contractId: contractId, precision: precision);
}
