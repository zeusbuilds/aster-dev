import 'package:objectbox/objectbox.dart';
import '../../../../core/core.dart';

/// Wallet data model for ObjectBox persistence
///
/// Represents a wallet with its ID, name, timestamps, and active status.
///
/// The wallet ID is deterministically generated from a seed phrase.
@Entity()
class WalletModel {
  @Id()
  int id = 0;

  /// Deterministic wallet ID derived from seed phrase
  ///
  /// Format: "1F29A3B4 C5D6E7F8" (display format)
  String walletId;

  /// Compact wallet ID (no spaces) for storage and queries
  @Index()
  String compactWalletId;

  /// Display name (currently derived from seed phrase)
  String name;

  /// Creation timestamp
  @Property(type: PropertyType.date)
  DateTime createdAt;

  /// Last update timestamp
  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// Whether this wallet is currently active
  bool isActive;

  WalletModel({
    this.id = 0,
    required this.walletId,
    required this.compactWalletId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = false,
  });

  /// Factory constructor to create from seed phrase
  factory WalletModel.fromSeedPhrase(String seedPhrase) {
    final now = DateTime.now();
    final compactId = WalletIdGenerator.generateCompactWalletId(seedPhrase);
    final displayId = WalletIdGenerator.generateWalletId(seedPhrase);
    final name = WalletIdGenerator.generateWalletName(seedPhrase);

    return WalletModel(
      walletId: displayId,
      compactWalletId: compactId,
      name: name,
      createdAt: now,
      updatedAt: now,
      isActive: false,
    );
  }

  /// Creates a copy of this wallet model with updated fields
  ///
  /// All parameters are optional - only provided fields will be updated
  ///
  /// Returns a new WalletModel instance with the updated values
  WalletModel copyWith({
    int? id,
    String? walletId,
    String? compactWalletId,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return WalletModel(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      compactWalletId: compactWalletId ?? this.compactWalletId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
