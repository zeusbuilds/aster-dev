/// Distinguishes Bitcoin's public Signet from UTEXO's separate Dev chain.
///
/// Both chains use the native `signet` network enum. That enum and the shared
/// genesis block therefore cannot establish which chain a wallet belongs to.
enum SignetDeployment {
  publicBitcoin('public'),
  utexoDev('dev-signet');

  const SignetDeployment(this.wireName);

  final String wireName;

  static SignetDeployment parse(String value) => switch (value) {
    'public' => SignetDeployment.publicBitcoin,
    'dev-signet' => SignetDeployment.utexoDev,
    _ => throw const FormatException('Unknown Signet deployment.'),
  };
}

/// Quarantine for deployment evidence that is not a usable wallet profile.
///
/// The current Dev contract export is missing, the recorded BFA.5 contract is
/// historical, and Aster's RGB_L1 runtime remains unqualified. Merely supplying
/// these service URLs or asset IDs must not bypass the explicit profile gate.
abstract final class UtexoDevSignetPolicy {
  static const currentAssetId =
      'rgb:A6k89KtR-e3oXqRP-uH3jUrz-LU_sYL3-hMZ0k3O-6u8DXbE';
  static const historicalBfa5AssetId =
      'rgb:fbkO6B_i-qyLXa6d-x3sAOaX-cx~vZB9-rxNSUle-9lXBTf8';
  static const historicalDevAssetId =
      'rgb:OG9No4hZ-UrxoWmR-09ohtOk-ppxBN7h-g~KkQro-ncKc9A4';

  static const quarantinedAssetIds = {
    currentAssetId,
    historicalBfa5AssetId,
    historicalDevAssetId,
  };

  static const quarantinedHosts = {
    'dev.esplora-01.mint.utexo.com',
    'dev.rgb-proxy.utexo.com',
    'dev.mint.utexo.com',
    'rgb-proxy.dev.utexo.com',
    'esplora-api.utexo.com',
  };

  /// Checks host identity independently of path, port, case or URL spelling.
  static bool isQuarantinedEndpoint(String? value) {
    // Ordinary endpoint validation owns malformed/oversized values. Do not
    // parse them before that boundary has enforced its allocation limit.
    if (value == null || value.length > 2048) return false;
    final uri = Uri.tryParse(value.contains('://') ? value : 'tcp://$value');
    final host = uri?.host.toLowerCase();
    if (host == null) return false;
    return quarantinedHosts.contains(host) ||
        (host.endsWith('.') &&
            quarantinedHosts.contains(host.substring(0, host.length - 1)));
  }
}
