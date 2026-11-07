import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import '../validation/validation.dart';
import 'bfa_mint_lock_policy.dart';
import 'host_address_policy.dart';
import 'rgb_contract_configuration.dart';
import 'signet_deployment.dart';

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

/// Identifies the native wallet format as well as the runtime implementation.
enum WalletBackend {
  rln('rln'),
  rgbL1('rgb-l1');

  const WalletBackend(this.wireName);

  final String wireName;

  /// Product activation gate; this does not certify release readiness.
  /// RGB_L1 stays closed while native/app qualification and authoritative RGB
  /// backup freshness remain unresolved.
  bool get activationAllowed => this == WalletBackend.rln;

  static WalletBackend parse(String value) => switch (value) {
    'rln' => WalletBackend.rln,
    'rgb-l1' => WalletBackend.rgbL1,
    _ => throw const AppConfigurationException(),
  };

  String sdkNetwork(
    BlockchainEnvironment environment, {
    SignetDeployment signetDeployment = SignetDeployment.publicBitcoin,
  }) =>
      environment == BlockchainEnvironment.signet &&
          (this == WalletBackend.rln ||
              signetDeployment == SignetDeployment.utexoDev)
      ? 'utexo'
      : environment.name;
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
    this.requiresEvmValidation = true,
    this.canonicalContract,
  });

  final String contractId;

  /// Decimal precision used to format integer asset-smallest units.
  final int precision;

  /// Whether this approved contract is a bridge-backed fungible asset.
  ///
  /// USDT defaults to BFA validation. An explicitly approved non-BFA regtest
  /// fixture may opt out; a ticker or precision cannot establish its schema.
  final bool requiresEvmValidation;

  /// Approved genesis definition; required by the RGB_L1 adapter before use.
  final RgbContractConfiguration? canonicalContract;

  @override
  bool operator ==(Object other) =>
      other is RgbAssetConfiguration &&
      other.contractId == contractId &&
      other.precision == precision &&
      other.requiresEvmValidation == requiresEvmValidation &&
      other.canonicalContract == canonicalContract;

  @override
  int get hashCode => Object.hash(
    contractId,
    precision,
    requiresEvmValidation,
    canonicalContract,
  );

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
    canonicalContract?.validate();
  }
}

/// Public, non-secret service configuration supplied to the wallet runtime.
@immutable
final class WalletServiceConfiguration {
  const WalletServiceConfiguration({
    required this.environment,
    required this.sdkNetwork,
    this.backend = WalletBackend.rln,
    this.signetDeployment = SignetDeployment.publicBitcoin,
    this.indexerUrl,
    this.rgbTransportProxy,
    this.lspBaseUrl,
    this.vssUrl,
    this.ethRpcUrl,
    this.ethChainId,
    this.bfaMintLockPolicy,
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
    final backend = WalletBackend.parse(
      const String.fromEnvironment('ASTER_WALLET_BACKEND', defaultValue: 'rln'),
    );
    final SignetDeployment signetDeployment;
    try {
      signetDeployment = SignetDeployment.parse(
        const String.fromEnvironment(
          'ASTER_SIGNET_DEPLOYMENT',
          defaultValue: 'public',
        ),
      );
    } on FormatException {
      throw const AppConfigurationException();
    }
    return WalletServiceConfiguration(
      environment: environment,
      sdkNetwork: backend.sdkNetwork(
        environment,
        signetDeployment: signetDeployment,
      ),
      backend: backend,
      signetDeployment: signetDeployment,
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
      ethChainId: _optionalEnvironment('ASTER_ETH_CHAIN_ID'),
      bfaMintLockPolicy: _mintLockEnvironment(),
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
        contractBase64: const String.fromEnvironment(
          'ASTER_USDT_CONTRACT_BASE64',
        ),
        contractSha256: const String.fromEnvironment(
          'ASTER_USDT_CONTRACT_SHA256',
        ),
        nativeName: const String.fromEnvironment('ASTER_USDT_NATIVE_NAME'),
        nativeTicker: const String.fromEnvironment('ASTER_USDT_NATIVE_TICKER'),
      ),
    );
  }

  final BlockchainEnvironment environment;

  /// Engine and on-disk wallet format selected at build time.
  final WalletBackend backend;

  /// Explicit chain deployment; UTEXO Dev is currently quarantined.
  final SignetDeployment signetDeployment;

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

  /// Deployment-approved EVM chain identity as a canonical decimal uint256.
  ///
  /// Bitcoin's network name does not identify the BFA backing chain. No chain
  /// is inferred from mainnet, an RPC URL, or an asset's display ticker.
  final String? ethChainId;

  /// Required explicit BFA.7 mint validation bounds for an RGB_L1 EVM service.
  final BfaMintLockPolicy? bfaMintLockPolicy;
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
      other.backend == backend &&
      other.signetDeployment == signetDeployment &&
      other.sdkNetwork == sdkNetwork &&
      other.daemonListeningPort == daemonListeningPort &&
      other.ldkPeerListeningPort == ldkPeerListeningPort &&
      other.indexerUrl == indexerUrl &&
      other.rgbTransportProxy == rgbTransportProxy &&
      other.lspBaseUrl == lspBaseUrl &&
      other.vssUrl == vssUrl &&
      other.ethRpcUrl == ethRpcUrl &&
      other.ethChainId == ethChainId &&
      other.bfaMintLockPolicy == bfaMintLockPolicy &&
      other.explorerBaseUrl == explorerBaseUrl &&
      other.usdtAsset == usdtAsset;

  @override
  int get hashCode => Object.hash(
    environment,
    backend,
    signetDeployment,
    sdkNetwork,
    daemonListeningPort,
    ldkPeerListeningPort,
    indexerUrl,
    rgbTransportProxy,
    lspBaseUrl,
    vssUrl,
    ethRpcUrl,
    ethChainId,
    bfaMintLockPolicy,
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
    // Fail before resolving native defaults, wallet storage or credentials.
    // Current Dev requires a compatible runtime, checkpoint-bound identity and
    // an approved current contract export; none can be inferred from Signet.
    if (signetDeployment != SignetDeployment.publicBitcoin ||
        UtexoDevSignetPolicy.quarantinedAssetIds.contains(
          usdtAsset?.contractId,
        ) ||
        [
          indexerUrl,
          rgbTransportProxy,
          lspBaseUrl,
          vssUrl,
          ethRpcUrl,
          explorerBaseUrl,
        ].any(UtexoDevSignetPolicy.isQuarantinedEndpoint)) {
      throw const AppConfigurationException();
    }
    final permitsInsecureDevelopmentEndpoints =
        !kReleaseMode && allowInsecureDevelopmentEndpoints;
    final expectedSdkNetwork = backend.sdkNetwork(
      environment,
      signetDeployment: signetDeployment,
    );
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
    if (backend == WalletBackend.rgbL1 &&
        usdtAsset != null &&
        (usdtAsset!.canonicalContract == null ||
            !usdtAsset!.requiresEvmValidation)) {
      throw const AppConfigurationException();
    }
    final expectedChain = ethChainId;
    final mintPolicy = bfaMintLockPolicy;
    try {
      mintPolicy?.validate();
    } on FormatException {
      throw const AppConfigurationException();
    }
    if ((mintPolicy != null &&
            (backend != WalletBackend.rgbL1 ||
                ethRpcUrl == null ||
                expectedChain == null)) ||
        (backend == WalletBackend.rgbL1 &&
            ethRpcUrl != null &&
            mintPolicy == null)) {
      throw const AppConfigurationException();
    }
    if (expectedChain != null &&
        (!isCanonicalEvmChainId(expectedChain) || ethRpcUrl == null)) {
      throw const AppConfigurationException();
    }
    if (backend == WalletBackend.rgbL1 &&
        (lspBaseUrl != null ||
            vssUrl != null ||
            (ethRpcUrl != null && expectedChain == null) ||
            (expectedChain != null &&
                BigInt.parse(expectedChain).bitLength > 64))) {
      throw const AppConfigurationException();
    }
    // Native RLN enables BFA schemas only with an EVM RPC. A public-network USDT
    // route must never be advertised while this validation is disabled or
    // while the backing chain's expected identity has not been supplied.
    if (usdtAsset != null &&
        (environment != BlockchainEnvironment.regtest ||
            usdtAsset!.requiresEvmValidation) &&
        (ethRpcUrl == null || expectedChain == null)) {
      throw const AppConfigurationException();
    }
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
    'ASTER_ETH_CHAIN_ID' => const String.fromEnvironment('ASTER_ETH_CHAIN_ID'),
    'ASTER_EXPLORER_URL' => const String.fromEnvironment('ASTER_EXPLORER_URL'),
    _ => '',
  };
  return value.isEmpty ? null : value;
}

final _transactionId = RegExp(r'^[0-9a-fA-F]{64}$');

BfaMintLockPolicy? _mintLockEnvironment() {
  try {
    return BfaMintLockPolicy.parse(
      const String.fromEnvironment('ASTER_BFA_MIN_MINT_LOCK_BLOCKS'),
      const String.fromEnvironment('ASTER_BFA_MAX_MINT_LOCK_BLOCKS'),
    );
  } on FormatException {
    throw const AppConfigurationException();
  }
}

/// EIP-155 chain identities are positive integers with at most 256 bits.
bool isCanonicalEvmChainId(String value) {
  if (value.length > 78 || !RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
    return false;
  }
  final parsed = BigInt.tryParse(value);
  return parsed != null && parsed.bitLength <= 256;
}

RgbAssetConfiguration? _rgbAssetEnvironment({
  required String contractId,
  required int precision,
  required String contractBase64,
  required String contractSha256,
  required String nativeName,
  required String nativeTicker,
}) {
  final hasContractId = contractId.isNotEmpty;
  final hasPrecision = precision >= 0;
  final contractFields = [
    contractBase64,
    contractSha256,
    nativeName,
    nativeTicker,
  ];
  final hasContract = contractFields.any((value) => value.isNotEmpty);
  if (!hasContractId && !hasPrecision && !hasContract) return null;
  if (!hasContractId || !hasPrecision) {
    throw const AppConfigurationException();
  }
  if (hasContract && contractFields.any((value) => value.isEmpty)) {
    throw const AppConfigurationException();
  }
  return RgbAssetConfiguration(
    contractId: contractId,
    precision: precision,
    requiresEvmValidation: true,
    canonicalContract: hasContract
        ? RgbContractConfiguration(
            contractBase64: contractBase64,
            sha256Digest: contractSha256,
            nativeName: nativeName,
            nativeTicker: nativeTicker,
          )
        : null,
  );
}
