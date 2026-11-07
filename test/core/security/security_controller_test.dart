import 'dart:async';

import 'package:aster/core/errors/errors.dart';
import 'package:aster/core/security/device_authentication.dart';
import 'package:aster/core/security/security_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('device security policy', () {
    test(
      'existing secured wallet stays locked until a successful prompt',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        expect(controller.appLockEnabled, isTrue);
        expect(controller.initialized, isTrue);
        expect(controller.isLocked, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(device.reasons, isEmpty);

        final prompt = device.nextPrompt();
        final unlocking = controller.unlock();
        await _flush();
        expect(controller.isAuthenticating, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(device.reasons, ['Unlock Aster']);
        prompt.complete(DeviceAuthenticationResult.authenticated);

        expect(await unlocking, isTrue);
        expect(controller.canAccessWallet, isTrue);
        expect(controller.isAuthenticating, isFalse);
      },
    );

    test(
      'first launch may reach Welcome before setup authentication',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        expect(controller.canAccessWallet, isTrue);
        expect(device.reasons, isEmpty);

        final grant = await controller.authorize(SecurityPurpose.walletSetup);
        expect(grant, isNotNull);
        expect(device.reasons, ['Set up your wallet']);
        controller.handleLifecycle(AppLifecycleState.paused);
        expect(
          controller.isLocked,
          isTrue,
          reason:
              'A recovery-phrase draft must be protected before provisioning.',
        );
      },
    );

    test(
      'explicitly unsecured device bypasses launch and every action',
      () async {
        final device = _Device()..security = DeviceSecurityStatus.unsecured;
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        expect(controller.canAccessWallet, isTrue);
        for (final purpose in SecurityPurpose.values) {
          final walletId =
              purpose == SecurityPurpose.revealSeed ||
                  purpose == SecurityPurpose.exportXpubs ||
                  purpose == SecurityPurpose.deleteWallet
              ? 'wallet-a'
              : null;
          final grant = await controller.authorize(purpose, walletId: walletId);
          expect(
            controller.consume(grant, purpose, walletId: walletId),
            isTrue,
          );
        }
        expect(await controller.setAppLockEnabled(false), isTrue);
        controller.lock();
        expect(controller.isLocked, isFalse);
        expect(device.reasons, isEmpty);
      },
    );

    test(
      'removed device credential permits access after a fresh status check',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        device.security = DeviceSecurityStatus.unsecured;
        expect(await controller.unlock(), isTrue);
        expect(controller.canAccessWallet, isTrue);
        expect(device.reasons, isEmpty);
      },
    );

    test(
      'unknown capability fails closed even without an existing wallet',
      () async {
        final device = _Device()
          ..statusError = StateError('private platform detail');
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        expect(controller.initialized, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(controller.deviceStatus, isNull);
        expect(
          controller.unlockError,
          'Device authentication is unavailable. Try again.',
        );
        expect(controller.unlockError, isNot(contains('private')));
        expect(await controller.unlock(), isFalse);
        expect(controller.isLocked, isTrue);
        expect(device.reasons, isEmpty);
      },
    );

    test(
      'cancel keeps the wallet locked and requires an explicit retry',
      () async {
        final device = _Device()..result = DeviceAuthenticationResult.cancelled;
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        expect(await controller.unlock(), isFalse);
        expect(controller.isLocked, isTrue);
        expect(controller.unlockError, isNull);
        await _flush();
        expect(device.reasons, hasLength(1));

        device.result = DeviceAuthenticationResult.authenticated;
        expect(await controller.unlock(), isTrue);
        expect(device.reasons, hasLength(2));
      },
    );

    test(
      'platform authentication failure never becomes unsecured bypass',
      () async {
        final device = _Device()
          ..authenticationError = StateError('private native error');
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        expect(await controller.unlock(), isFalse);
        expect(controller.isLocked, isTrue);
        expect(controller.deviceStatus, DeviceSecurityStatus.secured);
        expect(
          controller.unlockError,
          'Device authentication is unavailable. Try again.',
        );
      },
    );

    test(
      'unsecured prompt result requires authoritative unsecured status',
      () async {
        final device = _Device()..result = DeviceAuthenticationResult.unsecured;
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        expect(await controller.unlock(), isFalse);
        expect(controller.isLocked, isTrue);
        expect(controller.deviceStatus, DeviceSecurityStatus.secured);
      },
    );

    test('waitForUnlock never releases startup after cancellation', () async {
      final device = _Device()..result = DeviceAuthenticationResult.cancelled;
      final controller = _controller(device);
      await controller.initialize(hasWallet: true);
      var released = false;
      final waiting = controller.waitForUnlock().then((_) => released = true);
      await _flush();
      expect(released, isFalse);
      device.result = DeviceAuthenticationResult.authenticated;
      expect(await controller.unlock(), isTrue);
      await waiting;
      expect(released, isTrue);
    });
  });

  group('one-use sensitive authorization', () {
    test(
      'each disclosure needs a fresh grant even with app lock disabled',
      () async {
        final device = _Device();
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        expect(controller.canAccessWallet, isTrue);
        final first = await controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        expect(
          controller.consume(
            first,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isTrue,
        );
        expect(
          controller.consume(
            first,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        final second = await controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        expect(
          controller.consume(
            second,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isTrue,
        );
        expect(device.reasons, [
          'Reveal your recovery phrase',
          'Reveal your recovery phrase',
        ]);
      },
    );

    test(
      'grants are bound to their issuing controller, purpose and wallet',
      () async {
        final controller = _controller(_Device());
        final other = _controller(_Device());
        await controller.initialize(hasWallet: false);
        await other.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        other.updateWallet('wallet-a');
        final grant = await controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        expect(
          other.consume(
            grant,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        expect(
          controller.consume(
            grant,
            SecurityPurpose.exportXpubs,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        expect(
          controller.consume(
            grant,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-b',
          ),
          isFalse,
        );
        expect(
          controller.consume(
            grant,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isTrue,
        );
      },
    );

    test(
      'switching wallets rejects an in-flight prompt and old grants',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        final oldGrant = await controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        final prompt = device.nextPrompt();
        final pending = controller.authorize(
          SecurityPurpose.exportXpubs,
          walletId: 'wallet-a',
        );
        await _flush();
        controller.updateWallet('wallet-b');
        prompt.complete(DeviceAuthenticationResult.authenticated);
        expect(await pending, isNull);
        expect(
          controller.consume(
            oldGrant,
            SecurityPurpose.revealSeed,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        expect(device.cancelCount, 1);
      },
    );

    test('background revokes old grants even if app lock is off', () async {
      final controller = _controller(_Device(), appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');
      final grant = await controller.authorize(
        SecurityPurpose.revealSeed,
        walletId: 'wallet-a',
      );
      controller.handleLifecycle(AppLifecycleState.paused);
      expect(controller.canAccessWallet, isFalse);
      expect(controller.isLocked, isFalse);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(controller.canAccessWallet, isTrue);
      expect(
        controller.consume(
          grant,
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        ),
        isFalse,
      );
    });

    test(
      'capture hides sensitive content and invalidates a previous grant',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        final grant = await controller.authorize(
          SecurityPurpose.exportXpubs,
          walletId: 'wallet-a',
        );
        device.capture(true);
        expect(controller.sensitiveVisible, isFalse);
        device.capture(false);
        expect(controller.sensitiveVisible, isTrue);
        expect(
          controller.consume(
            grant,
            SecurityPurpose.exportXpubs,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
      },
    );

    test(
      'an explicit lock invalidates a pending sensitive authentication',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        final prompt = device.nextPrompt();
        final pending = controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        await _flush();
        controller.lock();
        prompt.complete(DeviceAuthenticationResult.authenticated);
        expect(await pending, isNull);
        expect(controller.isLocked, isTrue);
      },
    );

    test(
      'cancelled sensitive action yields no grant and leaves app unlocked',
      () async {
        final device = _Device()..result = DeviceAuthenticationResult.cancelled;
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        expect(await controller.authorize(SecurityPurpose.exportXpubs), isNull);
        expect(controller.canAccessWallet, isTrue);
        expect(controller.unlockError, isNull);
      },
    );

    test('parallel actions cannot share or stack system prompts', () async {
      final device = _Device();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      final prompt = device.nextPrompt();
      final first = controller.authorize(SecurityPurpose.changeAppLock);
      await _flush();
      expect(await controller.authorize(SecurityPurpose.walletSetup), isNull);
      expect(await controller.unlock(), isFalse);
      expect(device.reasons, hasLength(1));
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await first, isNotNull);
    });
  });

  group('wallet deletion authorization and empty registry', () {
    test('delete authenticates afresh when app lock is disabled', () async {
      final device = _Device();
      final controller = _controller(device, appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');

      for (var attempt = 0; attempt < 2; attempt++) {
        final grant = await controller.authorize(
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        );
        expect(
          controller.consume(
            grant,
            SecurityPurpose.deleteWallet,
            walletId: 'wallet-a',
          ),
          isTrue,
        );
        expect(
          controller.consume(
            grant,
            SecurityPurpose.deleteWallet,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
      }
      expect(device.reasons, ['Delete this wallet', 'Delete this wallet']);
      expect(controller.appLockEnabled, isFalse);
      expect(controller.canAccessWallet, isTrue);
    });

    test(
      'cancelled deletion authentication leaves wallet access intact',
      () async {
        final device = _Device()..result = DeviceAuthenticationResult.cancelled;
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        final generation = controller.generation;

        expect(
          await controller.authorize(
            SecurityPurpose.deleteWallet,
            walletId: 'wallet-a',
          ),
          isNull,
        );
        expect(controller.generation, generation);
        expect(controller.canAccessWallet, isTrue);
        expect(controller.unlockError, isNull);
        expect(device.reasons, ['Delete this wallet']);
      },
    );

    test('deletion failure never becomes an unsecured bypass', () async {
      final device = _Device()
        ..authenticationError = StateError('private native detail');
      final controller = _controller(device, appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');

      await expectLater(
        controller.authorize(
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        ),
        throwsA(
          isA<AppFailureException>().having(
            (value) => value.failure.userMessage,
            'safe failure',
            'Device authentication is unavailable. Try again.',
          ),
        ),
      );
      expect(controller.deviceStatus, DeviceSecurityStatus.secured);
      expect(controller.isAuthenticating, isFalse);
      expect(controller.canAccessWallet, isTrue);
    });

    test('deletion authorization is bound to wallet and purpose', () async {
      final controller = _controller(_Device(), appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');
      final grant = await controller.authorize(
        SecurityPurpose.deleteWallet,
        walletId: 'wallet-a',
      );
      expect(
        controller.consume(
          grant,
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        ),
        isFalse,
      );
      expect(
        controller.consume(
          grant,
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-b',
        ),
        isFalse,
      );
      controller.updateWallet('wallet-b');
      expect(
        controller.consume(
          grant,
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        ),
        isFalse,
      );
    });

    test('wallet switch rejects pending deletion authentication', () async {
      final device = _Device();
      final controller = _controller(device, appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');
      final prompt = device.nextPrompt();
      final pending = controller.authorize(
        SecurityPurpose.deleteWallet,
        walletId: 'wallet-a',
      );
      await _flush();
      controller.updateWallet('wallet-b');
      prompt.complete(DeviceAuthenticationResult.authenticated);

      expect(await pending, isNull);
      expect(device.cancelCount, 1);
      expect(controller.canAccessWallet, isTrue);
    });

    test(
      'real background revokes deletion even with app lock disabled',
      () async {
        final device = _Device();
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        final grant = await controller.authorize(
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        );
        device.background();
        controller.handleLifecycle(AppLifecycleState.paused);
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(await controller.prepareForeground(), isTrue);

        expect(
          controller.consume(
            grant,
            SecurityPurpose.deleteWallet,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        expect(device.reasons, ['Delete this wallet']);
      },
    );

    test('screen capture does not prohibit authenticated deletion', () async {
      final device = _Device();
      final controller = _controller(device, appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');
      device.capture(true);

      final grant = await controller.authorize(
        SecurityPurpose.deleteWallet,
        walletId: 'wallet-a',
      );
      expect(controller.sensitiveVisible, isFalse);
      expect(
        controller.consume(
          grant,
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        ),
        isTrue,
      );
    });

    test(
      'only committed empty registry clears setup and wallet protection',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        expect(
          await controller.authorize(SecurityPurpose.walletSetup),
          isNotNull,
        );
        controller.updateWallet('wallet-a');
        controller.updateWallet(null);
        controller.handleLifecycle(AppLifecycleState.paused);
        expect(
          controller.isLocked,
          isTrue,
          reason: 'A transient null wallet must preserve existing protection.',
        );
        controller.handleLifecycle(AppLifecycleState.resumed);

        controller.clearWalletPresence();
        expect(controller.canAccessWallet, isTrue);
        expect(controller.requiresUnlockAction, isFalse);
        expect(controller.appLockEnabled, isTrue);
        expect(controller.unlockError, isNull);
        device.reasons.clear();
        device.background();
        controller.handleLifecycle(AppLifecycleState.paused);
        expect(controller.isLocked, isFalse);
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(await controller.prepareForeground(), isTrue);
        expect(device.reasons, isEmpty);

        controller.updateWallet('wallet-b');
        controller.handleLifecycle(AppLifecycleState.paused);
        expect(
          controller.isLocked,
          isTrue,
          reason: 'A later wallet retains the user\'s app-lock preference.',
        );
      },
    );

    test(
      'committed last deletion revokes grants and cancels pending auth',
      () async {
        final device = _Device();
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        final grant = await controller.authorize(
          SecurityPurpose.deleteWallet,
          walletId: 'wallet-a',
        );
        final prompt = device.nextPrompt();
        final pending = controller.authorize(
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        );
        await _flush();

        controller.clearWalletPresence();
        prompt.complete(DeviceAuthenticationResult.authenticated);
        expect(await pending, isNull);
        expect(device.cancelCount, 1);
        expect(
          controller.consume(
            grant,
            SecurityPurpose.deleteWallet,
            walletId: 'wallet-a',
          ),
          isFalse,
        );
        expect(controller.appLockEnabled, isFalse);
        expect(controller.canAccessWallet, isTrue);
      },
    );

    test(
      'empty registry preserves background privacy and unknown capability',
      () async {
        final device = _Device();
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        controller.handleLifecycle(AppLifecycleState.paused);
        controller.clearWalletPresence();
        expect(controller.isObscured, isTrue);
        expect(controller.canAccessWallet, isFalse);
        controller.handleLifecycle(AppLifecycleState.resumed);
        device.statusError = StateError('capability unavailable');
        await expectLater(controller.refreshStatus(), throwsStateError);

        controller.clearWalletPresence();
        expect(controller.deviceStatus, isNull);
        expect(controller.isLocked, isTrue);
        expect(controller.requiresUnlockAction, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(device.reasons, isEmpty);
      },
    );
  });

  group('lifecycle and preferences', () {
    for (final unlocking in [false, true]) {
      test(
        'revocation at auth completion cannot ${unlocking ? 'unlock' : 'mint a grant'} '
        'even when app lock is disabled',
        () async {
          final controller = _controller(_Device(), appLockEnabled: false);
          await controller.initialize(hasWallet: true);
          var armed = false;
          controller.addListener(() {
            if (controller.isAuthenticating) {
              armed = true;
            } else if (armed) {
              armed = false;
              controller.lock();
            }
          });
          if (unlocking) {
            expect(await controller.unlock(), isFalse);
          } else {
            expect(
              await controller.authorize(SecurityPurpose.walletSetup),
              isNull,
            );
          }
          expect(controller.isAuthenticating, isFalse);
        },
      );
    }

    for (final purpose in SecurityPurpose.values) {
      test('owned $purpose keeps source visible without issuing authority '
          'until resume', () async {
        final device = _Device();
        final controller = _controller(device, appLockEnabled: false);
        await controller.initialize(hasWallet: true);
        controller.updateWallet('wallet-a');
        final generation = controller.generation;
        final prompt = device.nextPrompt();
        final pending = controller.authorize(purpose, walletId: 'wallet-a');
        await _flush();
        controller.handleLifecycle(AppLifecycleState.inactive);
        expect(controller.isObscured, isFalse);
        expect(controller.canAccessWallet, isFalse);
        expect(controller.sensitiveVisible, isFalse);
        expect(controller.generation, generation);
        prompt.complete(DeviceAuthenticationResult.authenticated);
        await _flush();
        expect(controller.isAuthenticating, isTrue);
        controller.handleLifecycle(AppLifecycleState.resumed);
        final grant = await pending;
        expect(
          controller.consume(grant, purpose, walletId: 'wallet-a'),
          isTrue,
        );
        expect(device.presentationFinishes, 1);
        expect(device.reasons, hasLength(1));
      });
    }

    test('unowned inactivity still obscures the route', () async {
      final controller = _controller(_Device());
      await controller.initialize(hasWallet: false);
      controller.handleLifecycle(AppLifecycleState.inactive);
      expect(controller.isObscured, isTrue);
      expect(controller.canAccessWallet, isFalse);
      expect(await controller.authorize(SecurityPurpose.walletSetup), isNull);
    });

    test('unrelated inactivity during capability RPC cannot acquire prompt '
        'ownership', () async {
      final device = _Device();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      final status = device.nextStatus();
      final pending = controller.authorize(SecurityPurpose.walletSetup);
      controller.handleLifecycle(AppLifecycleState.inactive);
      status.complete(DeviceSecurityStatus.secured);
      expect(await pending, isNull);
      expect(controller.isObscured, isTrue);
      expect(device.reasons, isEmpty);
      expect(device.presentationFinishes, 0);
    });

    test(
      'a failed OS prompt restores cover if host remains inactive',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        final prompt = device.nextPrompt();
        final pending = controller.authorize(SecurityPurpose.walletSetup);
        final checked = expectLater(
          pending,
          throwsA(isA<AppFailureException>()),
        );
        await _flush();
        controller.handleLifecycle(AppLifecycleState.inactive);
        prompt.completeError(StateError('OS interruption'));
        await checked;
        expect(controller.isAuthenticating, isFalse);
        expect(controller.isObscured, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(device.presentationFinishes, 1);
      },
    );

    test('capture during prompt revokes its result even if capture ends '
        'before success', () async {
      final device = _Device();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      controller.updateWallet('wallet-a');
      final prompt = device.nextPrompt();
      final pending = controller.authorize(
        SecurityPurpose.revealSeed,
        walletId: 'wallet-a',
      );
      await _flush();
      device.capture(true);
      device.capture(false);
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await pending, isNull);
      expect(device.cancelCount, 1);
      expect(device.presentationFinishes, 1);
    });

    test('late inactivity during native presentation cleanup waits for '
        'resume before granting', () async {
      final device = _Device()..presentationGate = Completer<void>();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      final pending = controller.authorize(SecurityPurpose.walletSetup);
      await _flush();
      expect(device.presentationFinishes, 1);
      controller.handleLifecycle(AppLifecycleState.inactive);
      device.presentationGate!.complete();
      await _flush();
      expect(controller.isAuthenticating, isTrue);
      expect(controller.isObscured, isFalse);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(await pending, isNotNull);
    });

    test(
      'native cleanup failure never grants access or strands input',
      () async {
        final device = _Device()
          ..presentationError = StateError('cleanup failed');
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        await expectLater(
          controller.authorize(SecurityPurpose.walletSetup),
          throwsA(isA<AppFailureException>()),
        );
        expect(controller.isAuthenticating, isFalse);
        expect(controller.isObscured, isFalse);
        expect(device.presentationFinishes, 1);
      },
    );

    test('native background overrides owned credential activity with app '
        'lock disabled', () async {
      final device = _Device();
      final controller = _controller(device, appLockEnabled: false);
      await controller.initialize(hasWallet: true);
      final prompt = device.nextPrompt();
      final pending = controller.authorize(SecurityPurpose.exportXpubs);
      await _flush();
      controller.handleLifecycle(AppLifecycleState.paused);
      expect(controller.isObscured, isFalse);
      device.background();
      expect(controller.isObscured, isTrue);
      controller.handleLifecycle(AppLifecycleState.resumed);
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await pending, isNull);
      expect(controller.isLocked, isFalse);
      expect(device.cancelCount, 1);
    });

    test('newly enabled device credential requires auth on foreground before access', () async {
      final device = _Device()..security = DeviceSecurityStatus.unsecured;
      final controller = _controller(device);
      await controller.initialize(hasWallet: true);
      controller.updateWallet('wallet-a');
      device.background();
      controller.handleLifecycle(AppLifecycleState.paused);
      device.security = DeviceSecurityStatus.secured;
      controller.handleLifecycle(AppLifecycleState.resumed);
      final status = device.nextStatus();
      final prompt = device.nextPrompt();
      final pending = controller.prepareForeground();
      expect(
        controller.canAccessWallet,
        isFalse,
        reason: 'The previous unsecured status cannot expose a wallet frame.',
      );
      status.complete(DeviceSecurityStatus.secured);
      await _flush();
      expect(device.reasons, ['Unlock Aster']);
      expect(controller.canAccessWallet, isFalse);
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await pending, isTrue);
      expect(controller.canAccessWallet, isTrue);
      expect(controller.deviceStatus, DeviceSecurityStatus.secured);
    });

    test(
      'removed device credential is recognized on foreground with no prompt',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        device.background();
        controller.handleLifecycle(AppLifecycleState.paused);
        device.security = DeviceSecurityStatus.unsecured;
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(await controller.prepareForeground(), isTrue);
        expect(controller.canAccessWallet, isTrue);
        expect(controller.deviceStatus, DeviceSecurityStatus.unsecured);
        expect(device.reasons, isEmpty);
      },
    );

    test(
      'failed foreground status after prior unsecured state fails closed',
      () async {
        final device = _Device()..security = DeviceSecurityStatus.unsecured;
        final controller = _controller(device);
        await controller.initialize(hasWallet: true);
        device.background();
        controller.handleLifecycle(AppLifecycleState.paused);
        device.statusError = StateError('private capability detail');
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(await controller.prepareForeground(), isFalse);
        expect(controller.deviceStatus, isNull);
        expect(controller.canAccessWallet, isFalse);
        expect(controller.isLocked, isTrue);
        expect(
          controller.unlockError,
          'Device authentication is unavailable. Try again.',
        );
        expect(device.reasons, isEmpty);
      },
    );

    test(
      'unknown first-launch status cannot release startup through background',
      () async {
        final device = _Device()..statusError = StateError('capability failed');
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        var released = false;
        unawaited(controller.waitForUnlock().then((_) => released = true));
        await _flush();
        device.background();
        controller.handleLifecycle(AppLifecycleState.paused);
        controller.handleLifecycle(AppLifecycleState.resumed);
        expect(await controller.prepareForeground(), isFalse);
        expect(controller.isLocked, isTrue);
        expect(controller.canAccessWallet, isFalse);
        expect(released, isFalse);
      },
    );

    test('owned cancelled unlock waits for resume then preserves manual retry '
        'without launching another prompt', () async {
      final device = _Device();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      controller.updateWallet('wallet-a');
      controller.lock();
      final prompt = device.nextPrompt();
      final unlocking = controller.unlock();
      await _flush();
      controller.handleLifecycle(AppLifecycleState.inactive);
      prompt.complete(DeviceAuthenticationResult.cancelled);
      await _flush();
      expect(
        controller.isAuthenticating,
        isTrue,
        reason: 'The system sheet still owns the foreground transition.',
      );
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(await unlocking, isFalse);
      expect(controller.isLocked, isTrue);
      expect(controller.requiresUnlockAction, isTrue);
      expect(await controller.prepareForeground(), isFalse);
      expect(controller.requiresUnlockAction, isTrue);
      expect(device.reasons, ['Unlock Aster']);
    });

    test('owned inactive/resumed prompt does not recursively lock', () async {
      final device = _Device();
      final controller = _controller(device);
      await controller.initialize(hasWallet: false);
      controller.updateWallet('wallet-a');
      final prompt = device.nextPrompt();
      final pending = controller.authorize(
        SecurityPurpose.revealSeed,
        walletId: 'wallet-a',
      );
      await _flush();
      controller.handleLifecycle(AppLifecycleState.inactive);
      expect(controller.sensitiveVisible, isFalse);
      controller.handleLifecycle(AppLifecycleState.resumed);
      prompt.complete(DeviceAuthenticationResult.authenticated);
      final grant = await pending;
      expect(
        controller.consume(
          grant,
          SecurityPurpose.revealSeed,
          walletId: 'wallet-a',
        ),
        isTrue,
      );
      expect(controller.isLocked, isFalse);
      expect(device.reasons, hasLength(1));
    });

    test(
      'credential activity waits for resumed before issuing its new grant',
      () async {
        final device = _Device();
        final controller = _controller(device);
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        final prompt = device.nextPrompt();
        var settled = false;
        final pending = controller
            .authorize(SecurityPurpose.exportXpubs, walletId: 'wallet-a')
            .then((value) {
              settled = true;
              return value;
            });
        await _flush();
        controller.handleLifecycle(AppLifecycleState.paused);
        prompt.complete(DeviceAuthenticationResult.authenticated);
        await _flush();
        expect(settled, isFalse);
        expect(controller.canAccessWallet, isFalse);
        controller.handleLifecycle(AppLifecycleState.resumed);
        final grant = await pending;
        expect(
          controller.consume(
            grant,
            SecurityPurpose.exportXpubs,
            walletId: 'wallet-a',
          ),
          isTrue,
        );
        expect(device.reasons, hasLength(1));
      },
    );

    for (final resumedBeforeCancellation in [false, true]) {
      test(
        'background during cancelled auth relocks the app '
        '${resumedBeforeCancellation ? 'even when resume wins the callback race' : 'before foreground return'}',
        () async {
          final device = _Device();
          final controller = _controller(device);
          await controller.initialize(hasWallet: false);
          controller.updateWallet('wallet-a');
          final prompt = device.nextPrompt();
          final pending = controller.authorize(
            SecurityPurpose.exportXpubs,
            walletId: 'wallet-a',
          );
          await _flush();
          device.background();
          controller.handleLifecycle(AppLifecycleState.paused);
          if (resumedBeforeCancellation) {
            controller.handleLifecycle(AppLifecycleState.resumed);
          }
          prompt.complete(DeviceAuthenticationResult.cancelled);
          expect(await pending, isNull);
          expect(controller.isLocked, isTrue);
          controller.handleLifecycle(AppLifecycleState.resumed);
          expect(controller.canAccessWallet, isFalse);
          expect(
            device.reasons,
            hasLength(1),
            reason: 'The failed action must not automatically relaunch auth.',
          );
        },
      );
    }

    test('real background locks established wallet immediately', () async {
      final controller = _controller(_Device());
      await controller.initialize(hasWallet: false);
      controller.updateWallet('wallet-a');
      controller.handleLifecycle(AppLifecycleState.paused);
      expect(controller.isLocked, isTrue);
      expect(controller.canAccessWallet, isFalse);
      controller.handleLifecycle(AppLifecycleState.resumed);
      expect(controller.isLocked, isTrue);
      expect(controller.canAccessWallet, isFalse);
    });

    test('lock preference changes authenticate before persistence', () async {
      final device = _Device();
      final writes = <bool>[];
      final controller = _controller(
        device,
        saveAppLock: (value) async {
          writes.add(value);
          return true;
        },
      );
      await controller.initialize(hasWallet: false);
      final prompt = device.nextPrompt();
      final pending = controller.setAppLockEnabled(false);
      await _flush();
      expect(writes, isEmpty);
      expect(controller.appLockEnabled, isTrue);
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await pending, isTrue);
      expect(writes, [false]);
      expect(controller.appLockEnabled, isFalse);
      expect(device.reasons, ['Change Aster app lock']);
    });

    test(
      'cancelled preference change neither persists nor changes policy',
      () async {
        final device = _Device()..result = DeviceAuthenticationResult.cancelled;
        final writes = <bool>[];
        final controller = _controller(
          device,
          saveAppLock: (value) async {
            writes.add(value);
            return true;
          },
        );
        await controller.initialize(hasWallet: false);
        expect(await controller.setAppLockEnabled(false), isFalse);
        expect(writes, isEmpty);
        expect(controller.appLockEnabled, isTrue);
      },
    );

    test('failed lock persistence preserves previous policy', () async {
      final controller = _controller(
        _Device(),
        saveAppLock: (_) async => false,
      );
      await controller.initialize(hasWallet: false);
      await expectLater(
        controller.setAppLockEnabled(false),
        throwsA(
          isA<AppFailureException>().having(
            (value) => value.failure.code,
            'code',
            'app_lock_save_failed',
          ),
        ),
      );
      expect(controller.appLockEnabled, isTrue);
    });

    test(
      'background during preference persistence restores prior lock policy',
      () async {
        final device = _Device();
        final saved = Completer<bool>();
        final writes = <bool>[];
        final controller = _controller(
          device,
          saveAppLock: (enabled) {
            writes.add(enabled);
            return writes.length == 1 ? saved.future : Future.value(true);
          },
        );
        await controller.initialize(hasWallet: false);
        controller.updateWallet('wallet-a');
        final pending = controller.setAppLockEnabled(false);
        await _flush();
        expect(writes, [false]);
        device.background();
        saved.complete(true);
        expect(await pending, isFalse);
        expect(writes, [false, true]);
        expect(controller.appLockEnabled, isTrue);
        expect(controller.isLocked, isTrue);
      },
    );

    test(
      'parallel preference changes cannot race durable policy writes',
      () async {
        final device = _Device();
        final saved = Completer<bool>();
        final writes = <bool>[];
        final controller = _controller(
          device,
          saveAppLock: (enabled) {
            writes.add(enabled);
            return writes.length == 1 ? saved.future : Future.value(true);
          },
        );
        await controller.initialize(hasWallet: false);
        final first = controller.setAppLockEnabled(false);
        await _flush();
        expect(await controller.setAppLockEnabled(true), isFalse);
        expect(await controller.setAppLockEnabled(false), isFalse);
        expect(writes, [false]);
        saved.complete(true);
        expect(await first, isTrue);
        expect(controller.appLockEnabled, isFalse);
        expect(await controller.setAppLockEnabled(true), isTrue);
        expect(writes, [false, true]);
        expect(controller.appLockEnabled, isTrue);
        expect(device.reasons, hasLength(2));
      },
    );

    test('disposed controller cannot accept late authentication', () async {
      final device = _Device();
      final controller = SecurityController(device);
      await controller.initialize(hasWallet: false);
      final prompt = device.nextPrompt();
      final pending = controller.authorize(SecurityPurpose.walletSetup);
      await _flush();
      controller.dispose();
      prompt.complete(DeviceAuthenticationResult.authenticated);
      expect(await pending, isNull);
      expect(device.cancelCount, 1);
      await device.close();
    });
  });
}

SecurityController _controller(
  _Device device, {
  Future<bool> Function(bool)? saveAppLock,
  bool appLockEnabled = true,
}) {
  final controller = SecurityController(
    device,
    saveAppLock: saveAppLock,
    appLockEnabled: appLockEnabled,
  );
  addTearDown(() async {
    controller.dispose();
    await device.close();
  });
  return controller;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Device
    implements
        DeviceAuthentication,
        DeviceAuthenticationBackgroundEvents,
        DeviceAuthenticationPresentation {
  DeviceSecurityStatus security = DeviceSecurityStatus.secured;
  DeviceAuthenticationResult result = DeviceAuthenticationResult.authenticated;
  Object? statusError;
  Object? authenticationError;
  final reasons = <String>[];
  final sensitiveValues = <bool>[];
  int cancelCount = 0;
  int presentationFinishes = 0;
  Completer<void>? presentationGate;
  Object? presentationError;
  bool _captured = false;
  Completer<DeviceAuthenticationResult>? _nextPrompt;
  Completer<DeviceSecurityStatus>? _nextStatus;
  final _capture = StreamController<bool>.broadcast(sync: true);
  final _background = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get backgroundEvents => _background.stream;

  void background() => _background.add(null);

  Completer<DeviceAuthenticationResult> nextPrompt() =>
      _nextPrompt = Completer<DeviceAuthenticationResult>();

  Completer<DeviceSecurityStatus> nextStatus() =>
      _nextStatus = Completer<DeviceSecurityStatus>();

  @override
  Future<DeviceSecurityStatus> status() async {
    if (statusError case final error?) throw error;
    final pending = _nextStatus;
    _nextStatus = null;
    return pending == null ? security : await pending.future;
  }

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    reasons.add(reason);
    if (authenticationError case final error?) throw error;
    final pending = _nextPrompt;
    _nextPrompt = null;
    return pending == null ? result : await pending.future;
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> finishAuthenticationPresentation() async {
    presentationFinishes++;
    if (presentationError case final error?) throw error;
    await presentationGate?.future;
  }

  @override
  bool get isCaptured => _captured;

  @override
  Stream<bool> get captureChanges => _capture.stream;

  void capture(bool value) {
    _captured = value;
    _capture.add(value);
  }

  @override
  Future<void> setSensitive(bool sensitive) async {
    sensitiveValues.add(sensitive);
  }

  Future<void> close() async {
    await _capture.close();
    await _background.close();
  }
}
