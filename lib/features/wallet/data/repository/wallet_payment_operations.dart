import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';
import '../runtime/runtime.dart';
import '../validation/validation.dart';

/// Generic queue callback supplied only by the owning wallet repository.
typedef WalletSerializedOperationRunner = Future<AppResult<T>> Function<T>(
  Future<AppResult<T>> Function() operation,
);

/// Owns route resolution, payment validation, and native payment reads/writes.
///
/// This implementation collaborator is deliberately not exported from the
/// repository barrel. [WalletRepository] supplies its single serialized
/// operation runner, so extracting policy cannot create a second native owner
/// or weaken ordering around wallet lifecycle mutations.
final class WalletPaymentOperations {
  const WalletPaymentOperations(
    this._runtime,
    this._services,
    this._bitcoinInstructions,
    this._runSerialized,
  );

  final WalletRuntime _runtime;
  final WalletServiceConfiguration _services;
  final BitcoinPaymentInstructionDecoder _bitcoinInstructions;
  final WalletSerializedOperationRunner _runSerialized;

  static const standardFeeTargetBlocks = 6;

  List<WalletPaymentCapability> get capabilities {
    final usdt = _services.usdtAsset;
    final capabilities = <WalletPaymentCapability>[
      WalletPaymentCapability.available(
        const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
      ),
      WalletPaymentCapability.available(
        const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.lightning,
        ),
      ),
      if (usdt == null) ...const [
        WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtOnchain),
        WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtLightning),
      ] else ...[
        WalletPaymentCapability.available(
          PaymentRoute(
            asset: WalletAsset.rgbUsdt(
              assetId: usdt.contractId,
              precision: usdt.precision,
            ),
            rail: PaymentRail.onchain,
          ),
        ),
        WalletPaymentCapability.available(
          PaymentRoute(
            asset: WalletAsset.rgbUsdt(
              assetId: usdt.contractId,
              precision: usdt.precision,
            ),
            rail: PaymentRail.lightning,
          ),
        ),
      ],
    ];
    return List<WalletPaymentCapability>.unmodifiable(capabilities);
  }

  AppResult<PaymentRoute> resolveTarget(WalletPaymentTarget target) {
    for (final capability in capabilities) {
      if (capability.target != target) continue;
      final route = capability.route;
      if (route != null) return AppResult.success(route);
      return AppResult.failure(
        const AppFailure(
          code: 'rgb_usdt_not_configured',
          kind: AppFailureKind.configuration,
          userMessage: 'USDT is not configured for this network.',
          retryable: false,
        ),
      );
    }
    return AppResult.failure(
      const AppFailure(
        code: 'payment_target_unknown',
        kind: AppFailureKind.validation,
        userMessage: 'Choose a supported asset and payment rail.',
        retryable: false,
      ),
    );
  }

  Future<AppResult<WalletBalance>> balance(WalletAssetKind kind) {
    final routeResult = resolveTarget(
      kind == WalletAssetKind.bitcoin
          ? WalletPaymentTarget.bitcoinOnchain
          : WalletPaymentTarget.usdtOnchain,
    );
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    return _runSerialized(
      () => _runtime.run((engine) => engine.getBalance(route.asset)),
    );
  }

  Future<AppResult<WalletFeeRateEstimate>> estimateFeeRate({
    int targetBlocks = standardFeeTargetBlocks,
  }) {
    if (targetBlocks < WalletFeeRateEstimate.minimumTargetBlocks ||
        targetBlocks > WalletFeeRateEstimate.maximumTargetBlocks) {
      return Future.value(AppResult.failure(_invalidFeeTargetFailure()));
    }
    return _runSerialized(
      () => _runtime.run((engine) => engine.estimateFeeRate(targetBlocks)),
    );
  }

  Future<AppResult<WalletPortfolio>> portfolio() {
    final usdtRoute = resolveTarget(WalletPaymentTarget.usdtOnchain);
    return _runSerialized(
      () => _runtime.run((engine) async {
        final bitcoin = await engine.getBalance(WalletAsset.bitcoin);
        final WalletBalance? usdt;
        if (usdtRoute case AppSuccess<PaymentRoute>(:final value)) {
          usdt = await engine.getBalance(value.asset);
        } else {
          usdt = null;
        }
        return WalletPortfolio(bitcoin: bitcoin, usdt: usdt);
      }),
    );
  }

  Future<AppResult<WalletActivityFeed>> activityFeed(WalletAssetKind kind) {
    final routeResult = resolveTarget(
      kind == WalletAssetKind.bitcoin
          ? WalletPaymentTarget.bitcoinOnchain
          : WalletPaymentTarget.usdtOnchain,
    );
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final asset = (routeResult as AppSuccess<PaymentRoute>).value.asset;
    return _runSerialized(
      () => _runtime.run((engine) async {
        final networkStatus = await engine.getNetworkStatus();
        final balance = await engine.getBalance(asset);
        final activities = await engine.listActivity(asset);
        return WalletActivityFeed(
          balance: balance,
          networkStatus: networkStatus,
          activities: activities,
        );
      }),
    );
  }

  Future<AppResult<WalletPaymentPreview>> preview(
    WalletPaymentTarget target,
    String destination,
  ) {
    final routeResult = resolveTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    if (target == WalletPaymentTarget.bitcoinOnchain) {
      final parsed = _bitcoinInstructions.decodeOnchain(
        destination,
        _services.environment,
      );
      return Future.value(switch (parsed) {
        AppSuccess<BitcoinDestination>(:final value) => AppResult.success(
          WalletPaymentPreview(
            route: route,
            encodedDestination: value.address,
            displayDestination: value.address,
            amount: value.amount,
            recipientLabel: value.recipientLabel,
            message: value.message,
          ),
        ),
        AppFailureResult<BitcoinDestination>(:final failure) =>
          AppResult.failure(failure),
      });
    }
    if (target == WalletPaymentTarget.bitcoinLightning) {
      final parsed = _bitcoinInstructions.extractLightning(destination);
      if (parsed case AppFailureResult<BitcoinLightningInstruction>(
        :final failure,
      )) {
        return Future.value(AppResult.failure(failure));
      }
      final instruction =
          (parsed as AppSuccess<BitcoinLightningInstruction>).value;
      return _runSerialized(() async {
        final decoded = await _runtime.run(
          (engine) => engine.decodeInvoice(route, instruction.invoice),
        );
        return switch (decoded) {
          AppSuccess<WalletPaymentPreview>(:final value) => AppResult.success(
            value.withDisplayMetadata(
              recipientLabel: instruction.recipientLabel,
              message: instruction.message,
            ),
          ),
          AppFailureResult<WalletPaymentPreview>(:final failure) =>
            AppResult.failure(failure),
        };
      });
    }
    if (!WalletProtocolText.isEncodedValue(destination)) {
      return Future.value(AppResult.failure(_invalidDestinationFailure()));
    }
    return _runSerialized(
      () => _runtime.run((engine) => engine.decodeInvoice(route, destination)),
    );
  }

  Future<AppResult<WalletReceiveRequest>> createReceiveRequest(
    WalletPaymentTarget target, {
    int? amountUnits,
  }) {
    final routeResult = resolveTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    if (amountUnits == null && target.requiresReceiveAmount) {
      return Future.value(AppResult.failure(_receiveAmountRequiredFailure()));
    }
    final amountResult = _amountForRoute(route, amountUnits);
    if (amountResult case AppFailureResult<WalletAmount?>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final amount = (amountResult as AppSuccess<WalletAmount?>).value;
    return _runSerialized(
      () => _runtime.run(
        (engine) => engine.createReceiveRequest(route, amount: amount),
      ),
    );
  }

  Future<AppResult<WalletSendResult>> send({
    required WalletPaymentTarget target,
    required String destination,
    required int amountUnits,
  }) {
    final routeResult = resolveTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    final amountResult = _amountForRoute(route, amountUnits);
    if (amountResult case AppFailureResult<WalletAmount?>(:final failure)) {
      return Future.value(AppResult.failure(failure));
    }
    final amount = (amountResult as AppSuccess<WalletAmount?>).value;
    if (amount == null) {
      return Future.value(AppResult.failure(_invalidAmountFailure()));
    }
    final String submissionDestination;
    if (target == WalletPaymentTarget.bitcoinOnchain) {
      final parsed = _bitcoinInstructions.decodeOnchain(
        destination,
        _services.environment,
      );
      if (parsed case AppFailureResult<BitcoinDestination>(:final failure)) {
        return Future.value(AppResult.failure(failure));
      }
      final bitcoinDestination =
          (parsed as AppSuccess<BitcoinDestination>).value;
      final encodedAmount = bitcoinDestination.amount;
      if (encodedAmount != null && encodedAmount != amount) {
        return Future.value(AppResult.failure(_amountMismatchFailure()));
      }
      submissionDestination = bitcoinDestination.address;
    } else if (target == WalletPaymentTarget.bitcoinLightning) {
      final parsed = _bitcoinInstructions.extractLightning(destination);
      if (parsed case AppFailureResult<BitcoinLightningInstruction>(
        :final failure,
      )) {
        return Future.value(AppResult.failure(failure));
      }
      submissionDestination =
          (parsed as AppSuccess<BitcoinLightningInstruction>).value.invoice;
    } else {
      if (!WalletProtocolText.isEncodedValue(destination)) {
        return Future.value(AppResult.failure(_invalidDestinationFailure()));
      }
      submissionDestination = destination;
    }
    if (route.rail == PaymentRail.onchain) {
      return _runSerialized(() async {
        final feeResult = await _runtime.run(
          (engine) => engine.estimateFeeRate(standardFeeTargetBlocks),
        );
        if (feeResult case AppFailureResult<WalletFeeRateEstimate>(
          :final failure,
        )) {
          return AppResult.failure(failure);
        }
        final command = WalletSendCommand(
          route: route,
          destination: submissionDestination,
          amount: amount,
          feeRate: (feeResult as AppSuccess<WalletFeeRateEstimate>).value,
        );
        return _runtime.run((engine) => engine.sendPayment(command));
      });
    }
    final command = WalletSendCommand(
      route: route,
      destination: submissionDestination,
      amount: amount,
    );
    return _runSerialized(
      () => _runtime.run((engine) => engine.sendPayment(command)),
    );
  }

  static AppResult<WalletAmount?> _amountForRoute(
    PaymentRoute route,
    int? units,
  ) {
    if (units == null) return const AppResult.success(null);
    if (units <= 0 || units > WalletAmount.maxNativeUnits) {
      return AppResult.failure(_invalidAmountFailure());
    }
    final amount = route.rail == PaymentRail.onchain
        ? WalletAmount.onchain(assetId: route.asset.id, units: units)
        : WalletAmount.lightning(assetId: route.asset.id, units: units);
    return AppResult.success(amount);
  }

  static AppFailure _invalidAmountFailure() => const AppFailure(
    code: 'payment_amount_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid amount greater than zero.',
    retryable: false,
  );

  static AppFailure _receiveAmountRequiredFailure() => const AppFailure(
    code: 'payment_receive_amount_required',
    kind: AppFailureKind.validation,
    userMessage: 'Enter an amount to create this payment request.',
    retryable: false,
  );

  static AppFailure _invalidDestinationFailure() => const AppFailure(
    code: 'payment_destination_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid payment destination.',
    retryable: false,
  );

  static AppFailure _invalidFeeTargetFailure() => const AppFailure(
    code: 'payment_fee_target_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Choose a valid confirmation target.',
    retryable: false,
  );

  static AppFailure _amountMismatchFailure() => const AppFailure(
    code: 'payment_amount_mismatch',
    kind: AppFailureKind.validation,
    userMessage: 'The entered amount does not match the payment request.',
    retryable: false,
  );
}
