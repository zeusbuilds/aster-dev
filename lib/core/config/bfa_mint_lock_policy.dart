/// Deployment-approved external EVM lock duration accepted for BFA mint validation.
///
/// Values count backing-chain blocks, not Bitcoin blocks. There is
/// no production default; the issuer/bridge must approve the matching policy.
final class BfaMintLockPolicy {
  const BfaMintLockPolicy({
    required this.minimumBlocks,
    required this.maximumBlocks,
  });

  final int minimumBlocks;
  final int maximumBlocks;

  void validate() {
    if (minimumBlocks < 2 || maximumBlocks < minimumBlocks) {
      throw const FormatException('BFA mint lock bounds are invalid.');
    }
  }

  static BfaMintLockPolicy? parse(String minimum, String maximum) {
    if (minimum.isEmpty && maximum.isEmpty) return null;
    final min = int.tryParse(minimum);
    final max = int.tryParse(maximum);
    if (min == null || max == null || '$min' != minimum || '$max' != maximum) {
      throw const FormatException(
        'BFA mint lock bounds must be canonical decimals.',
      );
    }
    final policy = BfaMintLockPolicy(minimumBlocks: min, maximumBlocks: max);
    policy.validate();
    return policy;
  }

  @override
  bool operator ==(Object other) =>
      other is BfaMintLockPolicy &&
      other.minimumBlocks == minimumBlocks &&
      other.maximumBlocks == maximumBlocks;

  @override
  int get hashCode => Object.hash(minimumBlocks, maximumBlocks);
}
