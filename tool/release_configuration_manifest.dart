import 'dart:collection';
import 'dart:convert';

import 'package:aster/core/config/bfa_mint_lock_policy.dart';
import 'package:aster/core/config/rgb_contract_policy.dart';
import 'package:aster/core/config/signet_deployment.dart';

/// Maximum accepted byte length of one release-configuration manifest.
const maximumReleaseConfigurationBytes = 64 * 1024;

/// Deployment audience selected for a candidate artifact.
enum ReleaseAudience {
  /// An engineering or internal-testing artifact that is not publicly listed.
  internalBeta,

  /// An artifact intended for App Store or Google Play distribution.
  publicDistribution,
}

/// Parses the command-line spelling used by owned release targets.
ReleaseAudience parseReleaseAudience(String value) => switch (value) {
  'internal-beta' => ReleaseAudience.internalBeta,
  'public-distribution' => ReleaseAudience.publicDistribution,
  _ => throw const FormatException(
    'Audience must be internal-beta or public-distribution.',
  ),
};

/// Canonical compile-time keys accepted by Aster release builds.
abstract final class ReleaseConfigurationKey {
  static const network = 'ASTER_NETWORK';
  static const walletBackend = 'ASTER_WALLET_BACKEND';
  static const signetDeployment = 'ASTER_SIGNET_DEPLOYMENT';
  static const daemonPort = 'ASTER_DAEMON_PORT';
  static const ldkPeerPort = 'ASTER_LDK_PEER_PORT';
  static const indexerUrl = 'ASTER_INDEXER_URL';
  static const rgbProxyUrl = 'ASTER_RGB_PROXY_URL';
  static const lspUrl = 'ASTER_LSP_URL';
  static const vssUrl = 'ASTER_VSS_URL';
  static const ethRpcUrl = 'ASTER_ETH_RPC_URL';
  static const ethChainId = 'ASTER_ETH_CHAIN_ID';
  static const bfaMinMintLockBlocks = 'ASTER_BFA_MIN_MINT_LOCK_BLOCKS';
  static const bfaMaxMintLockBlocks = 'ASTER_BFA_MAX_MINT_LOCK_BLOCKS';
  static const explorerUrl = 'ASTER_EXPLORER_URL';
  static const usdtAssetId = 'ASTER_USDT_ASSET_ID';
  static const usdtPrecision = 'ASTER_USDT_PRECISION';
  static const usdtContractBase64 = 'ASTER_USDT_CONTRACT_BASE64';
  static const usdtContractSha256 = 'ASTER_USDT_CONTRACT_SHA256';
  static const usdtNativeName = 'ASTER_USDT_NATIVE_NAME';
  static const usdtNativeTicker = 'ASTER_USDT_NATIVE_TICKER';
  static const marketApiBaseUrl = 'ASTER_MARKET_API_BASE_URL';
  static const supportUrl = 'ASTER_SUPPORT_URL';
  static const termsUrl = 'ASTER_TERMS_URL';
  static const privacyUrl = 'ASTER_PRIVACY_URL';
  static const twitterUrl = 'ASTER_TWITTER_URL';
  static const telegramUrl = 'ASTER_TELEGRAM_URL';
  static const instagramUrl = 'ASTER_INSTAGRAM_URL';

  static const all = <String>{
    bfaMinMintLockBlocks,
    bfaMaxMintLockBlocks,
    daemonPort,
    ethChainId,
    ethRpcUrl,
    explorerUrl,
    indexerUrl,
    instagramUrl,
    lspUrl,
    ldkPeerPort,
    marketApiBaseUrl,
    network,
    privacyUrl,
    rgbProxyUrl,
    signetDeployment,
    supportUrl,
    telegramUrl,
    termsUrl,
    twitterUrl,
    usdtAssetId,
    usdtPrecision,
    usdtContractBase64,
    usdtContractSha256,
    usdtNativeName,
    usdtNativeTicker,
    vssUrl,
    walletBackend,
  };

  static const internalRequired = <String>{
    ethChainId,
    ethRpcUrl,
    explorerUrl,
    indexerUrl,
    network,
    rgbProxyUrl,
    usdtAssetId,
    usdtPrecision,
    vssUrl,
  };

  static const publicRequired = <String>{
    ...internalRequired,
    marketApiBaseUrl,
    privacyUrl,
    supportUrl,
    termsUrl,
  };
}

/// Validated, immutable release configuration read from a JSON manifest.
final class ReleaseConfigurationManifest {
  ReleaseConfigurationManifest._(this.audience, Map<String, String> values)
    : values = UnmodifiableMapView(Map<String, String>.from(values));

  /// Parses and validates a UTF-8 JSON object for [audience].
  factory ReleaseConfigurationManifest.parse(
    String source, {
    required ReleaseAudience audience,
  }) {
    // UTF-8 is never shorter than Dart's UTF-16 code-unit count. Reject an
    // obviously oversized value before allocating a second encoded copy.
    if (source.length > maximumReleaseConfigurationBytes ||
        utf8.encode(source).length > maximumReleaseConfigurationBytes) {
      throw const FormatException('Release configuration is too large.');
    }
    final Map<String, String> decoded;
    try {
      decoded = _StrictStringJsonObjectParser(source).parse();
    } on FormatException {
      throw const FormatException('Release configuration is not valid JSON.');
    }

    final keys = decoded.keys.toList(growable: false);
    final sortedKeys = keys.toList()..sort();
    if (!_orderedEquals(keys, sortedKeys)) {
      throw const FormatException('Release configuration keys must be sorted.');
    }
    final unknown = keys.toSet().difference(ReleaseConfigurationKey.all);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Release configuration contains unknown keys: '
        '${(unknown.toList()..sort()).join(', ')}.',
      );
    }

    final values = <String, String>{};
    for (final MapEntry(:key, :value) in decoded.entries) {
      if (value.isEmpty || value != value.trim()) {
        throw FormatException('$key must be a non-empty trimmed string.');
      }
      final supportedText = key == ReleaseConfigurationKey.usdtNativeName
          ? value.length <= 256 &&
                value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e)
          : _isVisibleAscii(
              value,
              maximumCharacters:
                  key == ReleaseConfigurationKey.usdtContractBase64
                  ? RgbContractPolicy.maximumEncodedCharacters
                  : 2048,
            );
      if (!supportedText) {
        throw FormatException('$key contains unsupported characters.');
      }
      if (_looksLikePlaceholder(value)) {
        throw FormatException('$key still contains a placeholder value.');
      }
      values[key] = value;
    }

    final deployment = SignetDeployment.parse(
      values[ReleaseConfigurationKey.signetDeployment] ?? 'public',
    );
    if (deployment != SignetDeployment.publicBitcoin ||
        UtexoDevSignetPolicy.quarantinedAssetIds.contains(
          values[ReleaseConfigurationKey.usdtAssetId],
        ) ||
        const [
          ReleaseConfigurationKey.indexerUrl,
          ReleaseConfigurationKey.rgbProxyUrl,
          ReleaseConfigurationKey.lspUrl,
          ReleaseConfigurationKey.vssUrl,
          ReleaseConfigurationKey.ethRpcUrl,
          ReleaseConfigurationKey.explorerUrl,
        ].any(
          (key) => UtexoDevSignetPolicy.isQuarantinedEndpoint(values[key]),
        )) {
      throw const FormatException(
        'UTEXO Dev Signet is unqualified; its endpoints and assets '
        'cannot be used by a public Signet or RLN build.',
      );
    }

    const contractKeys = {
      ReleaseConfigurationKey.usdtContractBase64,
      ReleaseConfigurationKey.usdtContractSha256,
      ReleaseConfigurationKey.usdtNativeName,
      ReleaseConfigurationKey.usdtNativeTicker,
    };
    final configuredContractKeys = contractKeys.intersection(
      values.keys.toSet(),
    );
    if (configuredContractKeys.isNotEmpty) {
      if (configuredContractKeys.length != contractKeys.length) {
        throw const FormatException(
          'Approved RGB contract fields must be supplied together.',
        );
      }
      RgbContractPolicy.validate(
        contractBase64: values[ReleaseConfigurationKey.usdtContractBase64]!,
        sha256Digest: values[ReleaseConfigurationKey.usdtContractSha256]!,
        nativeName: values[ReleaseConfigurationKey.usdtNativeName]!,
        nativeTicker: values[ReleaseConfigurationKey.usdtNativeTicker]!,
      );
    }

    final mintPolicy = BfaMintLockPolicy.parse(
      values[ReleaseConfigurationKey.bfaMinMintLockBlocks] ?? '',
      values[ReleaseConfigurationKey.bfaMaxMintLockBlocks] ?? '',
    );
    if (mintPolicy != null &&
        (values[ReleaseConfigurationKey.walletBackend] ?? 'rln') != 'rgb-l1') {
      throw const FormatException(
        'BFA mint lock bounds require the RGB_L1 backend.',
      );
    }

    switch (values[ReleaseConfigurationKey.walletBackend] ?? 'rln') {
      case 'rln':
        break;
      case 'rgb-l1':
        throw const FormatException(
          'RGB_L1 requires verified durable payment recovery before release.',
        );
      default:
        throw const FormatException(
          'ASTER_WALLET_BACKEND must be rln or rgb-l1.',
        );
    }

    final required = audience == ReleaseAudience.publicDistribution
        ? ReleaseConfigurationKey.publicRequired
        : ReleaseConfigurationKey.internalRequired;
    final missing = required.difference(values.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'Release configuration is missing required keys: '
        '${(missing.toList()..sort()).join(', ')}.',
      );
    }

    _validateNetwork(values[ReleaseConfigurationKey.network]!);
    if (audience == ReleaseAudience.publicDistribution &&
        values[ReleaseConfigurationKey.network] != 'mainnet') {
      throw const FormatException(
        'Public distribution requires ASTER_NETWORK=mainnet.',
      );
    }
    final daemonPort = _validateListenerPort(
      values[ReleaseConfigurationKey.daemonPort] ?? '9735',
    );
    final peerPort = _validateListenerPort(
      values[ReleaseConfigurationKey.ldkPeerPort] ?? '9736',
    );
    if (daemonPort == peerPort) {
      throw const FormatException('Native listener ports must differ.');
    }
    _validateEndpoint(
      values[ReleaseConfigurationKey.indexerUrl]!,
      key: ReleaseConfigurationKey.indexerUrl,
      schemes: const {'https', 'ssl'},
      requirePortFor: const {'ssl'},
    );
    _validateEndpoint(
      values[ReleaseConfigurationKey.rgbProxyUrl]!,
      key: ReleaseConfigurationKey.rgbProxyUrl,
      schemes: const {'https', 'rpcs'},
    );
    for (final key in const [
      ReleaseConfigurationKey.vssUrl,
      ReleaseConfigurationKey.explorerUrl,
    ]) {
      _validatePublicHttps(values[key]!, key: key);
    }
    _validateAsset(
      values[ReleaseConfigurationKey.usdtAssetId]!,
      values[ReleaseConfigurationKey.usdtPrecision]!,
    );
    final expectedEvmChain = values[ReleaseConfigurationKey.ethChainId]!;
    if (expectedEvmChain.length > 78 ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(expectedEvmChain) ||
        BigInt.parse(expectedEvmChain).bitLength > 256) {
      throw const FormatException(
        'ASTER_ETH_CHAIN_ID must be a canonical positive decimal uint256.',
      );
    }

    final market = values[ReleaseConfigurationKey.marketApiBaseUrl];
    if (market != null) {
      final uri = _validatePublicHttps(
        market,
        key: ReleaseConfigurationKey.marketApiBaseUrl,
      );
      final host = uri.host.toLowerCase();
      if (host == 'api.coingecko.com' || host == 'pro-api.coingecko.com') {
        throw const FormatException(
          'ASTER_MARKET_API_BASE_URL must be an Aster-owned proxy.',
        );
      }
    }
    for (final key in const [
      ReleaseConfigurationKey.ethRpcUrl,
      ReleaseConfigurationKey.lspUrl,
      ReleaseConfigurationKey.supportUrl,
      ReleaseConfigurationKey.termsUrl,
      ReleaseConfigurationKey.privacyUrl,
      ReleaseConfigurationKey.twitterUrl,
      ReleaseConfigurationKey.telegramUrl,
      ReleaseConfigurationKey.instagramUrl,
    ]) {
      final value = values[key];
      if (value != null) _validatePublicHttps(value, key: key);
    }

    if (audience == ReleaseAudience.publicDistribution &&
        values.containsKey(ReleaseConfigurationKey.vssUrl)) {
      // Current RLN VSS restore omits the durable on-chain outbox, and the SDK
      // refuses recoverable sends when VSS is enabled. Keep the backup gate
      // until one qualified deployment can satisfy both requirements.
      throw const FormatException(
        'Public distribution requires backup and restore that preserve '
        'durable on-chain payment recovery. Current RLN VSS is incompatible.',
      );
    }
    return ReleaseConfigurationManifest._(audience, values);
  }

  /// Candidate audience whose required-key policy was applied.
  final ReleaseAudience audience;

  /// Validated non-secret compile-time values in deterministic source order.
  final Map<String, String> values;
}

/// Minimal strict parser for the only JSON shape Flutter dart-defines accept.
///
/// `jsonDecode` deliberately applies last-key-wins semantics. A release
/// manifest must instead reject duplicate keys, including duplicates written
/// with JSON escapes, so the reviewed text has one unambiguous meaning.
final class _StrictStringJsonObjectParser {
  _StrictStringJsonObjectParser(this._source);

  final String _source;
  var _offset = 0;

  Map<String, String> parse() {
    final values = <String, String>{};
    _skipWhitespace();
    _expect('{');
    _skipWhitespace();
    if (_consume('}')) {
      _requireEnd();
      return values;
    }

    while (true) {
      final key = _readString();
      if (values.containsKey(key)) {
        throw const FormatException('Duplicate JSON object key.');
      }
      _skipWhitespace();
      _expect(':');
      _skipWhitespace();
      final value = _readString();
      values[key] = value;
      _skipWhitespace();
      if (_consume('}')) break;
      _expect(',');
      _skipWhitespace();
      if (_peek == '}') {
        throw const FormatException('Trailing JSON object comma.');
      }
    }
    _requireEnd();
    return values;
  }

  String _readString() {
    if (_peek != '"') {
      throw const FormatException(
        'JSON object keys and values must be strings.',
      );
    }
    final start = _offset;
    _offset += 1;
    while (_offset < _source.length) {
      final unit = _source.codeUnitAt(_offset);
      if (unit == 0x22) {
        _offset += 1;
        final decoded = jsonDecode(_source.substring(start, _offset));
        if (decoded is! String) {
          throw const FormatException('JSON string is malformed.');
        }
        _skipWhitespace();
        return decoded;
      }
      if (unit < 0x20) {
        throw const FormatException(
          'JSON string contains a control character.',
        );
      }
      if (unit == 0x5c) {
        _offset += 1;
        if (_offset >= _source.length) {
          throw const FormatException('JSON escape is truncated.');
        }
        final escape = _source.codeUnitAt(_offset);
        if (escape == 0x75) {
          if (_offset + 4 >= _source.length) {
            throw const FormatException('JSON unicode escape is truncated.');
          }
          for (var index = 1; index <= 4; index += 1) {
            if (!_isHex(_source.codeUnitAt(_offset + index))) {
              throw const FormatException('JSON unicode escape is malformed.');
            }
          }
          _offset += 5;
          continue;
        }
        if (!const {
          0x22,
          0x2f,
          0x5c,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        }.contains(escape)) {
          throw const FormatException('JSON escape is malformed.');
        }
      }
      _offset += 1;
    }
    throw const FormatException('JSON string is unterminated.');
  }

  void _skipWhitespace() {
    while (_offset < _source.length &&
        const {0x20, 0x09, 0x0a, 0x0d}.contains(_source.codeUnitAt(_offset))) {
      _offset += 1;
    }
  }

  void _expect(String character) {
    if (!_consume(character)) {
      throw FormatException('Expected JSON token $character.');
    }
  }

  bool _consume(String character) {
    if (_peek != character) return false;
    _offset += 1;
    return true;
  }

  void _requireEnd() {
    _skipWhitespace();
    if (_offset != _source.length) {
      throw const FormatException('JSON contains trailing content.');
    }
  }

  String? get _peek => _offset < _source.length ? _source[_offset] : null;
}

bool _isHex(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x46) ||
    (unit >= 0x61 && unit <= 0x66);

void _validateNetwork(String value) {
  if (!const {'mainnet', 'signet', 'regtest'}.contains(value)) {
    throw const FormatException(
      'ASTER_NETWORK must be mainnet, signet, or regtest.',
    );
  }
}

int _validateListenerPort(String value) {
  final port = int.tryParse(value);
  if (port == null || '$port' != value || port < 1 || port > 65535) {
    throw const FormatException(
      'Native listener ports must be integers from 1 through 65535.',
    );
  }
  return port;
}

void _validateAsset(String contractId, String rawPrecision) {
  if (!_isVisibleAscii(contractId, maximumCharacters: 512)) {
    throw const FormatException('ASTER_USDT_ASSET_ID is malformed.');
  }
  final precision = int.tryParse(rawPrecision);
  if (precision == null ||
      '$precision' != rawPrecision ||
      precision < 0 ||
      precision > 18) {
    throw const FormatException(
      'ASTER_USDT_PRECISION must be an integer from 0 through 18.',
    );
  }
}

Uri _validatePublicHttps(String raw, {required String key}) {
  final uri = _validateEndpoint(raw, key: key, schemes: const {'https'});
  if (!_isCanonicalPublicDnsName(uri.host)) {
    throw FormatException('$key must use a canonical public DNS host.');
  }
  return uri;
}

Uri _validateEndpoint(
  String raw, {
  required String key,
  required Set<String> schemes,
  Set<String> requirePortFor = const {},
}) {
  final uri = Uri.tryParse(raw);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      scheme == null ||
      !schemes.contains(scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      !_isCanonicalPublicDnsName(uri.host) ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
      (requirePortFor.contains(scheme) && !uri.hasPort)) {
    throw FormatException('$key is not an approved release endpoint.');
  }
  return uri;
}

bool _isCanonicalPublicDnsName(String raw) {
  final host = raw.toLowerCase();
  if (host.isEmpty ||
      host.length > 253 ||
      !host.contains('.') ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains(':')) {
    return false;
  }
  final labels = host.split('.');
  if (!labels.every(
    (label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        RegExp(r'^[a-z0-9-]+$').hasMatch(label) &&
        !label.startsWith('-') &&
        !label.endsWith('-'),
  )) {
    return false;
  }
  if (!RegExp('[a-z]').hasMatch(labels.last)) return false;
  return !_nonPublicSuffixes.any(
    (suffix) => host == suffix || host.endsWith('.$suffix'),
  );
}

bool _isVisibleAscii(String value, {required int maximumCharacters}) =>
    value.isNotEmpty &&
    value.length <= maximumCharacters &&
    value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7e);

bool _looksLikePlaceholder(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('replace_me') ||
      normalized.contains('replace-me') ||
      normalized.contains('<') ||
      normalized.contains('>') ||
      normalized.contains('.example') ||
      normalized.contains('.invalid');
}

bool _orderedEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

const _nonPublicSuffixes = <String>{
  'example',
  'home',
  'internal',
  'invalid',
  'lan',
  'local',
  'localhost',
  'test',
};
