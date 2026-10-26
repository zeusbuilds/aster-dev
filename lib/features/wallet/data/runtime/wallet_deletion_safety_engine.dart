/// Native asset audit before irreversible RGB wallet removal.
abstract interface class WalletDeletionSafetyEngine {
  /// Returns true for any RGB holdings or nonterminal receive/send operation.
  /// May synchronize and expire a provably unfulfilled native receive request.
  /// Never dispatches or resumes a send. Unknown state never grants deletion.
  Future<bool> hasProtectedRgbState();
}
