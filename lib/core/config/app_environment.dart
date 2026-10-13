import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import '../validation/validation.dart';
import 'host_address_policy.dart';

/// Bitcoin chain environment, independent from asset and payment rail.
enum BlockchainEnvironment {
  mainnet,
  signet,
  regtest;

  /// Parses the canonical app-owned chain-environment representation.
  ///
  /// Asset names and protocol-specific network carriers are deliberately not
  /// accepted here. Native wire aliases are translated inside the SDK adapter.
  static BlockchainEnvironment parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'mainnet' => BlockchainEnvironment.mainnet,
      'signet' => BlockchainEnvironment.signet,
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
    this.ethRpcUrl,
    this.explorerBaseUrl,
    this.usdtAsset,
    this.daemonListeningPort = 9735,
    this.ldkPeerListeningPort = 9736,
  });

  /// Maximum serialized length of any endpoint crossing the native boundary.
  static const maximumEndpointCharacters = 2048;

  /// Reads compile-time configuration without embedding credentials.
  ///
  /// Regtest is deliberately the default so an unconfigured build cannot
  /// become a funds-bearing mainnet wallet by accident.
  factory WalletServiceConfiguration.fromEnvironment() {
    const networkValue = String.fromEnvironment(
      'ASTER_NETWORK',
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
      daemonListeningPort: _listenerPort(
        const String.fromEnvironment('ASTER_DAEMON_PORT', defaultValue: '9735'),
      ),
      ldkPeerListeningPort: _listenerPort(
        const String.fromEnvironment(
          'ASTER_LDK_PEER_PORT',
          defaultValue: '9736',
        ),
      ),
      indexerUrl: _optionalEnvironment('ASTER_INDEXER_URL'),
      rgbTransportProxy: _optionalEnvironment('ASTER_RGB_PROXY_URL'),
      lspBaseUrl: _optionalEnvironment('ASTER_LSP_URL'),
      vssUrl: _optionalEnvironment('ASTER_VSS_URL'),
      ethRpcUrl: _optionalEnvironment('ASTER_ETH_RPC_URL'),
      explorerBaseUrl:
          _optionalEnvironment('ASTER_EXPLORER_URL') ??
          switch (environment) {
            BlockchainEnvironment.mainnet => 'https://mempool.space',
            BlockchainEnvironment.signet => 'https://mempool.space/signet',
            BlockchainEnvironment.regtest => null,
          },
      usdtAsset: _rgbAssetEnvironment(
        contractId: const String.fromEnvironment('ASTER_USDT_ASSET_ID'),
        precision: const int.fromEnvironment(
          'ASTER_USDT_PRECISION',
          defaultValue: -1,
        ),
      ),
    );
  }

  final BlockchainEnvironment environment;

  /// Stable SDK network carrier. UTEXO protocol signet uses the SDK's `utexo`
  /// service profile while Aster still reports the chain as `signet`.
  final String sdkNetwork;

  /// Native node listener, separate from the outbound service endpoints.
  /// Local simulator builds must reserve their own port on the host.
  final int daemonListeningPort;

  /// Native Lightning peer listener. Must differ from [daemonListeningPort].
  /// This does not provision a peer, channel, or any Lightning liquidity.
  final int ldkPeerListeningPort;
  final String? indexerUrl;
  final String? rgbTransportProxy;
  final String? lspBaseUrl;
  final String? vssUrl;

  /// Credential-free Ethereum RPC used by native BFA validation, when enabled.
  /// This is not an Ethereum wallet or proof of an external bridge payout.
  final String? ethRpcUrl;
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
      other.daemonListeningPort == daemonListeningPort &&
      other.ldkPeerListeningPort == ldkPeerListeningPort &&
      other.indexerUrl == indexerUrl &&
      other.rgbTransportProxy == rgbTransportProxy &&
      other.lspBaseUrl == lspBaseUrl &&
      other.vssUrl == vssUrl &&
      other.ethRpcUrl == ethRpcUrl &&
      other.explorerBaseUrl == explorerBaseUrl &&
      other.usdtAsset == usdtAsset;

  @override
  int get hashCode => Object.hash(
    environment,
    sdkNetwork,
    daemonListeningPort,
    ldkPeerListeningPort,
    indexerUrl,
    rgbTransportProxy,
    lspBaseUrl,
    vssUrl,
    ethRpcUrl,
    explorerBaseUrl,
    usdtAsset,
  );

  /// Whether the validated VSS endpoint is an HTTP development endpoint.
  ///
  /// The SDK defaults to rejecting HTTP VSS. This opt-in is derived only after
  /// the app's Debug/Profile regtest policy has accepted the endpoint. Release
  /// builds never opt the native SDK into insecure VSS transport.
  bool get allowsInsecureLocalVss {
    final value = vssUrl;
    if (kReleaseMode ||
        value == null ||
        environment != BlockchainEnvironment.regtest) {
      return false;
    }
    final uri = Uri.parse(value);
    return uri.scheme.toLowerCase() == 'http' &&
        (HostAddressPolicy.isLoopback(uri.host) || uri.host == '10.0.2.2');
  }

  /// Validates URL policy before any native wallet is created.
  ///
  /// Insecure loopback transport is a local Debug/Profile capability, not a
  /// property of regtest itself. The explicit parameter is a deterministic
  /// test seam; it cannot weaken the Release-mode policy.
  void validate({bool allowInsecureDevelopmentEndpoints = !kReleaseMode}) {
    final permitsInsecureDevelopmentEndpoints =
        !kReleaseMode && allowInsecureDevelopmentEndpoints;
    final expectedSdkNetwork = environment == BlockchainEnvironment.signet
        ? 'utexo'
        : environment.name;
    if (sdkNetwork != expectedSdkNetwork ||
        daemonListeningPort < 1 ||
        daemonListeningPort > 65535 ||
        ldkPeerListeningPort < 1 ||
        ldkPeerListeningPort > 65535 ||
        daemonListeningPort == ldkPeerListeningPort) {
      throw const AppConfigurationException();
    }
    _validateEndpoint(
      indexerUrl,
      _EndpointKind.indexer,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    _validateEndpoint(
      rgbTransportProxy,
      _EndpointKind.rgbTransport,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    _validateEndpoint(
      lspBaseUrl,
      _EndpointKind.webService,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    _validateEndpoint(
      vssUrl,
      _EndpointKind.webService,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    _validateEndpoint(
      explorerBaseUrl,
      _EndpointKind.explorer,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    _validateEndpoint(
      ethRpcUrl,
      _EndpointKind.webService,
      environment,
      permitsInsecureDevelopmentEndpoints,
    );
    usdtAsset?.validate();
  }

  static int _listenerPort(String value) {
    final port = int.tryParse(value);
    if (port == null || '$port' != value || port < 1 || port > 65535) {
      throw const AppConfigurationException();
    }
    return port;
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
    bool allowInsecureDevelopmentEndpoints,
  ) {
    if (raw == null) return;
    if (!_isSafeEndpointWireValue(raw)) {
      throw const AppConfigurationException();
    }
    final hasExplicitScheme = raw.contains('://');
    if (!hasExplicitScheme && kind != _EndpointKind.indexer) {
      throw const AppConfigurationException();
    }
    final uri = Uri.tryParse(hasExplicitScheme ? raw : 'tcp://$raw');
    if (uri == null ||
        uri.host.isEmpty ||
        !HostAddressPolicy.isCanonicalEndpointHost(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const AppConfigurationException();
    }
    final developmentHost =
        environment == BlockchainEnvironment.regtest &&
        (HostAddressPolicy.isLoopback(uri.host) || uri.host == '10.0.2.2');
    if (developmentHost &&
        uri.hasPort &&
        _protectedDevelopmentPorts.contains(uri.port)) {
      throw const AppConfigurationException();
    }
    final permitsInsecureTransport =
        developmentHost && allowInsecureDevelopmentEndpoints;
    final allowed = switch (kind) {
      _EndpointKind.indexer =>
        permitsInsecureTransport
            ? const {'http', 'https', 'tcp', 'ssl'}
            : const {'https', 'ssl'},
      _EndpointKind.rgbTransport =>
        permitsInsecureTransport
            ? const {'http', 'https', 'rpc', 'rpcs'}
            : const {'https', 'rpcs'},
      _EndpointKind.webService =>
        permitsInsecureTransport ? const {'http', 'https'} : const {'https'},
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

  static bool _isSafeEndpointWireValue(String value) {
    if (!ProtocolTextPolicy.isVisibleAscii(
      value,
      maximumCharacters: maximumEndpointCharacters,
    )) {
      return false;
    }
    try {
      return ProtocolTextPolicy.isVisibleAscii(
        Uri.decodeFull(value),
        maximumCharacters: maximumEndpointCharacters,
      );
    } on FormatException {
      return false;
    }
  }

  /// Ports owned by the unrelated `rgb-lightning-node-perf-lab` project.
  static const _protectedDevelopmentPorts = {18443, 50001, 3000};
}

enum _EndpointKind { indexer, rgbTransport, webService, explorer }

String? _optionalEnvironment(String name) {
  final value = switch (name) {
    'ASTER_INDEXER_URL' => const String.fromEnvironment('ASTER_INDEXER_URL'),
    'ASTER_RGB_PROXY_URL' => const String.fromEnvironment(
      'ASTER_RGB_PROXY_URL',
    ),
    'ASTER_LSP_URL' => const String.fromEnvironment('ASTER_LSP_URL'),
    'ASTER_VSS_URL' => const String.fromEnvironment('ASTER_VSS_URL'),
    'ASTER_ETH_RPC_URL' => const String.fromEnvironment('ASTER_ETH_RPC_URL'),
    'ASTER_EXPLORER_URL' => const String.fromEnvironment('ASTER_EXPLORER_URL'),
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
