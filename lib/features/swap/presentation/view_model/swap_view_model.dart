import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'swap_view_model.g.dart';

/// Owns target selection while swap execution remains unavailable by policy.
@riverpod
class SwapViewModel extends _$SwapViewModel {
  @override
  Future<SwapState> build() async {
    final capabilities = await ref.watch(
      walletPaymentCapabilitiesProvider.future,
    );
    return _initialState(capabilities);
  }

  /// Retries capability loading only when the typed failure permits replay.
  void retry() {
    final failure = switch (state) {
      AsyncError(:final error, :final stackTrace) => FailureMapper.from(
        error,
        stackTrace,
      ),
      _ => null,
    };
    if (failure == null || !failure.retryable) return;
    ref.invalidate(walletPaymentCapabilitiesProvider);
    ref.invalidateSelf();
  }

  bool selectFrom(WalletPaymentTarget target) =>
      _select(target, updateFrom: true);

  bool selectTo(WalletPaymentTarget target) =>
      _select(target, updateFrom: false);

  bool reverse() {
    final current = state.value;
    if (current == null || !current.canReverse) return false;
    state = AsyncData(current.copyWith(from: current.to, to: current.from));
    return true;
  }

  bool _select(WalletPaymentTarget target, {required bool updateFrom}) {
    final current = state.value;
    if (current == null) return false;
    final capability = current.capabilities
        .where((item) => item.target == target)
        .firstOrNull;
    if (capability?.isAvailable != true) return false;
    if ((updateFrom ? current.to : current.from) == target &&
        !current.canReverse) {
      return false;
    }
    if (updateFrom) {
      if (target == current.from) return false;
      state = AsyncData(
        target == current.to
            ? current.copyWith(from: target, to: current.from)
            : current.copyWith(from: target),
      );
      return true;
    }
    if (target == current.to) return false;
    state = AsyncData(
      target == current.from
          ? current.copyWith(from: current.to, to: target)
          : current.copyWith(to: target),
    );
    return true;
  }

  static SwapState _initialState(List<WalletPaymentCapability> capabilities) {
    final available = capabilities
        .where((item) => item.isAvailable)
        .map((item) => item.target)
        .toList(growable: false);
    final from = available.firstOrNull ?? WalletPaymentTarget.bitcoinOnchain;
    final alternatives = available.where((target) => target != from);
    final preferredTo = alternatives.contains(WalletPaymentTarget.usdtOnchain)
        ? WalletPaymentTarget.usdtOnchain
        : alternatives.firstOrNull ??
              (from == WalletPaymentTarget.usdtOnchain
                  ? WalletPaymentTarget.bitcoinOnchain
                  : WalletPaymentTarget.usdtOnchain);
    return SwapState(capabilities: capabilities, from: from, to: preferredTo);
  }
}
