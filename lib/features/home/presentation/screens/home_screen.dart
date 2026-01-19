import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/presentation/viewmodels/viewmodels.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gdk_flutter/gdk_flutter.dart';
import 'package:gdk_flutter/src/models/gdk_wallet_models.dart';

/// Main home screen displaying wallet balance, Bitcoin price, and asset list
///
/// Manages GDK session and balance fetching for the active wallet
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  GDKIsolateSession? _session;
  GdkBalance? _balance;
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Ticker forces a rebuild every frame for animated static
    _ticker = createTicker((elapsed) {
      setState(() {
        // Time-based animation updates can be added here if needed
      });
    });
    _ticker.start();
  }

  /// Logs into GDK with the active wallet and fetches the balance
  ///
  /// Creates a new GDK session, connects to the network, and retrieves balance information
  Future<void> _loginAndFetchBalances(WidgetRef ref) async {
    final walletState = ref.read(walletViewModelProvider);
    final activeWallet = walletState.activeWallet;

    if (activeWallet == null) {
      return;
    }

    try {
      final viewModel = ref.read(walletViewModelProvider.notifier);
      final seedPhrase = await viewModel.getSeedPhrase(
        activeWallet.compactWalletId,
      );

      if (seedPhrase == null) {
        return;
      }

      _session?.dispose();

      final session = await GDK.createSession();

      await session.connect(
        network: 'electrum-liquid',
        useTor: false,
        gapLimit: 20,
      );

      await session.login(mnemonic: seedPhrase);

      final subaccounts = await session.getSubaccounts();

      if (subaccounts.isNotEmpty) {
        final walletBalance = await session.getBalance(
          subaccount: subaccounts.first.pointer,
        );

        if (!mounted) return;
        setState(() {
          _balance = walletBalance;
          _session = session;
        });
      }
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('GDK home login/balance error: $e');
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Listen to wallet changes and login with active wallet
    ref.listen<WalletState>(walletViewModelProvider, (previous, next) {
      if (next.isLoading) {
        return;
      }

      final previousWalletId = previous?.activeWallet?.compactWalletId;
      final nextWalletId = next.activeWallet?.compactWalletId;

      // Login when wallet changes or when we first get an active wallet
      if (next.activeWallet != null &&
          (previousWalletId != nextWalletId || _session == null)) {
        _session?.dispose();
        _session = null;
        _loginAndFetchBalances(ref);
      }
    });

    return Scaffold(
      backgroundColor: colors.fill1,
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.4,
                width: double.infinity,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const MeshGradientBackground(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: MediaQuery.of(context).padding.top),
                          const HomeHeader(),
                          const PriceCard(),
                          SizedBox(height: context.spacing.spacing16),
                          const HomeActionButtons(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AssetsSection(balance: _balance),
            ],
          ),
        ],
      ),
    );
  }
}
