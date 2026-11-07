import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/data/validation/validation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors AppLoader's security-first lifecycle forwarding for this entrypoint.
///
/// The campaign bootstraps its isolated container before pumping AsterApp and
/// therefore does not mount the ordinary AppLoader. AsterApp deliberately
/// defers prompt lifecycle ownership to that outer layer. Omitting this bridge
/// would let a native auth result race the actual foreground acknowledgement.
class FullWalletQaSecurityLifecycle extends StatefulWidget {
  const FullWalletQaSecurityLifecycle({
    super.key,
    required this.security,
    required this.child,
  });

  final SecurityController security;
  final Widget child;

  @override
  State<FullWalletQaSecurityLifecycle> createState() =>
      _FullWalletQaSecurityLifecycleState();
}

class _FullWalletQaSecurityLifecycleState
    extends State<FullWalletQaSecurityLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Register before the child AsterApp, matching the production outer owner.
    WidgetsBinding.instance.addObserver(this);
    widget.security.handleLifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.security.handleLifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Real platform storage with a separate, retained namespace for each QA run.
/// No wallet, signer, repository, transport or cryptographic implementation is
/// substituted. Failed runs retain their files and encrypted records.
final class FullWalletQaStorage {
  FullWalletQaStorage._(this.runId, this.root);

  final String runId;
  final Directory root;

  static Future<FullWalletQaStorage> open({
    required String runId,
    required bool existing,
    Future<void> Function(Directory root)? restoreMissing,
  }) async {
    if (kReleaseMode ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$').hasMatch(runId)) {
      throw const FullWalletQaFailure('qa_run_configuration_invalid');
    }
    final support = await getApplicationSupportDirectory();
    const security = PlatformWalletStorageSecurity();
    final parent = Directory('${support.path}/aster_full_wallet_qa');
    await security.prepareRoot(parent.path);
    final root = Directory('${parent.path}/$runId');
    var present = await root.exists();
    if (!present && existing && restoreMissing != null) {
      await restoreMissing(root);
      present = await root.exists();
    }
    if (present != existing) {
      throw FullWalletQaFailure(
        existing ? 'qa_retained_store_missing' : 'qa_run_already_exists',
      );
    }
    if (!present) {
      await security.prepareRoot(root.path);
    }
    return FullWalletQaStorage._(runId, root);
  }

  Future<ProviderContainer> bootstrap({
    Future<void> Function(Map<String, Object?> evidence)? onFailureLogs,
    WalletServiceConfiguration? qualifiedLocalL1Services,
    Map<String, Object?>? readOnlyCheckpoint,
    Future<void> Function(Map<String, Object?> evidence)? onReadOnlyAudit,
  }) async {
    if (kReleaseMode || (qualifiedLocalL1Services != null && !kDebugMode)) {
      throw const FullWalletQaFailure('qa_run_configuration_invalid');
    }
    const security = PlatformWalletStorageSecurity();
    final secureStorage = SecureStorageService(
      storage: FlutterSecureStorage(
        iOptions: IOSOptions(
          accountName: 'com.aster.qa.$runId',
          accessibility: KeychainAccessibility.unlocked_this_device,
          synchronizable: false,
        ),
        aOptions: AndroidOptions(
          resetOnError: false,
          migrateOnAlgorithmChange: true,
          migrateWithBackup: false,
          keyCipherAlgorithm:
              KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
          storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
          storageNamespace: 'aster_qa_$runId',
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        // This run-isolated harness qualifies real financial/runtime flows,
        // not interactive UI authentication. Keep device capability checks
        // real and disclosure authorization enforced, while explicitly
        // disabling the app-lock prompt for this process only. Never persist
        // or inherit this policy in the normal application preferences.
        securityControllerProvider.overrideWith((ref) {
          final authentication = SecurityController(
            PlatformDeviceAuthentication(),
            appLockEnabled: false,
          );
          ref.onDispose(authentication.dispose);
          return authentication;
        }),
        if (qualifiedLocalL1Services != null) ...[
          walletServiceConfigurationProvider.overrideWith(
            (ref) => qualifiedLocalL1Services,
          ),
          walletEngineFactoryProvider.overrideWith(
            (ref) => _LocalL1QualificationFactory(
              ref.watch(bitcoinPaymentInstructionDecoderProvider),
              ref.watch(utcClockProvider),
            ),
          ),
          walletRuntimeProvider.overrideWith((ref) async {
            final factory = ref.watch(walletEngineFactoryProvider);
            final secrets = ref.watch(walletSecretStoreProvider);
            final directories = await ref.watch(
              walletDirectoryManagerProvider.future,
            );
            if (!ref.mounted || directories is! IoWalletDirectoryManager) {
              throw const FullWalletQaFailure('qa_storage_owner_invalid');
            }
            final runtime = WalletRuntime.forQualification(
              factory,
              directories,
              secrets,
              qualifiedLocalL1Services,
            );
            ref.onDispose(() => unawaited(runtime.dispose()));
            return runtime;
          }),
        ],
        sharedPreferencesProvider.overrideWith((ref) => preferences),
        secureStorageServiceProvider.overrideWithValue(secureStorage),
        walletDirectoryManagerProvider.overrideWith(
          (ref) async => IoWalletDirectoryManager(
            '${root.path}/native',
            security,
            deleteDirectory: (directory) async {
              try {
                final evidence = await _retainFailureLogs(directory, security);
                await onFailureLogs?.call(evidence);
              } catch (_) {
                // Private diagnostics must never change production rollback
                // success, retain an unintended live owner or hide its cause.
              } finally {
                await directory.delete(recursive: true);
              }
            },
          ),
        ),
        walletRegistryDocumentStoreProvider.overrideWith(
          (ref) async =>
              IoWalletRegistryDocumentStore('${root.path}/metadata', security),
        ),
      ],
    );
    // Initialization still fails closed when native capability is unknown.
    // No native wallet or credential is opened before this policy is ready.
    await container
        .read(securityControllerProvider)
        .initialize(hasWallet: true);
    if (readOnlyCheckpoint != null) {
      if (qualifiedLocalL1Services == null) {
        container.dispose();
        throw const FullWalletQaFailure('qa_readonly_local_l1_required');
      }
      final repository = await container.read(walletRepositoryProvider.future);
      try {
        // Validate READY metadata before selecting an open. The ordinary app
        // bootstrap may finish staged provisioning/deletion, so it is not used
        // by this observational process-reopen proof.
        final registry = requireQaSuccess(
          await repository.load(),
          'readonly_registry',
        );
        final active = registry.activeProfile;
        if (active == null ||
            registry.profiles.length != 1 ||
            registry.readyProfiles.length != 1 ||
            active.id != readOnlyCheckpoint['wallet_id']) {
          throw const FullWalletQaFailure('qa_readonly_registry_changed');
        }
        final runtime = await container.read(walletRuntimeProvider.future);
        requireQaSuccess(
          await runtime.verifyStorage(registry.readyProfiles),
          'readonly_storage',
        );
        requireQaSuccess(
          await runtime.restore(active),
          'readonly_existing_open',
        );
        final pending = requireQaSuccess(
          await runtime.readPaymentState((engine) async {
            if (engine is! WalletPaymentDiscoveryEngine) {
              throw const FullWalletQaFailure(
                'qa_readonly_native_audit_missing',
              );
            }
            return (engine as WalletPaymentDiscoveryEngine)
                .discoverPendingPaymentOperations();
          }),
          'readonly_native_pending',
        );
        final appPending = requireQaSuccess(
          await repository.paymentSubmissionStatus(),
          'readonly_app_pending',
        );
        if (pending.isNotEmpty || appPending?.requiresReconciliation == true) {
          throw const FullWalletQaFailure('qa_readonly_pending_operation');
        }
        await onReadOnlyAudit?.call({
          'wallet_id': active.id,
          'native_pending_count': 0,
          'app_pending_fence': false,
          'generic_refresh_invoked': false,
          'maintenance_bootstrap_invoked': false,
        });
        return container;
      } catch (_) {
        await repository.dispose();
        container.dispose();
        rethrow;
      }
    }
    return bootstrapApplicationContainer(container);
  }

  Future<Map<String, Object?>> _retainFailureLogs(
    Directory directory,
    WalletStorageSecurity security,
  ) async {
    final files = <String>[];
    var skipped = 0;
    final walletId = directory.path.split(Platform.pathSeparator).last;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(walletId)) {
      throw const FullWalletQaFailure('qa_log_owner_invalid');
    }
    final parent = Directory('${root.path}/failed_logs');
    await security.prepareRoot(parent.path);
    final destination = Directory('${parent.path}/$walletId');
    await security.prepareRoot(destination.path);
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.log')) continue;
      final relative = entity.path.substring(directory.path.length + 1);
      final segments = relative.split(Platform.pathSeparator);
      if (segments.any(
        (part) =>
            part == '.' ||
            part == '..' ||
            !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(part),
      )) {
        skipped += 1;
        continue;
      }
      // Native logs contain private debugging data and never leave this 0700
      // tree. The platform writer enforces 0600 files. A setup failure should
      // produce a small UTF-8 log; oversized/binary files are not serialized.
      if (files.length >= 32 || await entity.length() > 1024 * 1024) {
        skipped += 1;
        continue;
      }
      try {
        var current = destination.path;
        for (final segment in segments.take(segments.length - 1)) {
          current = '$current/$segment';
          await security.prepareRoot(current);
        }
        final target = '$current/${segments.last}';
        if (await File(target).exists()) {
          skipped += 1;
          continue;
        }
        final text = await entity.readAsString();
        if (text.isEmpty) {
          skipped += 1;
          continue;
        }
        await security.replaceTextFile(target, text);
        files.add(relative);
      } catch (_) {
        skipped += 1;
      }
    }
    return {
      'copied_count': files.length,
      'copied_files': files,
      'skipped_count': skipped,
    };
  }
}

/// Integration-entrypoint composition only; no product flag can select it.
/// Every cryptographic, storage and SDK operation still uses the real engine.
final class _LocalL1QualificationFactory implements WalletEngineFactory {
  const _LocalL1QualificationFactory(this.addresses, this.clock);

  final BitcoinAddressValidator addresses;
  final DateTime Function() clock;

  @override
  WalletEngine create(WalletEngineConfiguration configuration) {
    final services = configuration.services;
    if (!kDebugMode ||
        services.backend != WalletBackend.rgbL1 ||
        services.environment != BlockchainEnvironment.regtest ||
        services.signetDeployment != SignetDeployment.publicBitcoin) {
      throw const FullWalletQaFailure('qa_local_l1_profile_required');
    }
    services.validate();
    return RgbLibWalletEngine(
      services,
      storageDirectory: configuration.storageDirectory,
      bitcoinAddresses: addresses,
      clock: clock,
    );
  }
}

/// Public-only test coordination. Financial calls are never retried here.
/// Polling only reads a command acknowledgement; event publication has no
/// automatic retry. Host receipts must preserve an uncertain mutation outcome.
final class FullWalletQaControl {
  FullWalletQaControl({
    required this.runId,
    required String controlUrl,
    this.readOnly = false,
    this.beforeFinancialDispatch,
    int initialSequence = 0,
  }) : role = Platform.isIOS ? 'app-ios27' : 'app-android17',
       _base = Uri.parse(controlUrl),
       _sequence = initialSequence {
    if (_base.scheme != 'http' ||
        _base.host != '127.0.0.1' ||
        _base.port != 29671 ||
        _base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment ||
        !['', '/'].contains(_base.path)) {
      throw const FullWalletQaFailure('qa_control_url_invalid');
    }
    _client.connectionTimeout = const Duration(seconds: 10);
  }

  final String runId;
  final bool readOnly;
  final VoidCallback? beforeFinancialDispatch;
  final String role;
  final Uri _base;
  final HttpClient _client = HttpClient();
  int _sequence;

  Future<void> event(
    String event, [
    Map<String, Object?> fields = const {},
  ]) async {
    _rejectReservedFields(fields);
    await _publish(event, fields);
  }

  Future<void> _publish(String event, Map<String, Object?> fields) async {
    final financial = const {
      'fund_requested',
      'identity_requested',
      'bfa_mint_requested',
      'bfa_burn_requested',
      'btc_confirm_requested',
      'rgb_witness_funding_requested',
      'rgb_setup_confirm_requested',
    }.contains(event);
    if (readOnly && financial) {
      throw const FullWalletQaFailure(
        'qa_read_only_financial_request_rejected',
      );
    }
    if (financial) beforeFinancialDispatch?.call();
    validatePublicFields(fields);
    final request = await _client.postUrl(_base.resolve('/event'));
    if (financial) beforeFinancialDispatch?.call();
    request.headers.contentType = ContentType.json;
    final payload = utf8.encode(
      jsonEncode({
        ...fields,
        'event': event,
        'run_id': runId,
        'role': role,
        'time_utc': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    request.contentLength = payload.length;
    request.add(payload);
    final response = await request.close().timeout(const Duration(seconds: 15));
    await _body(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FullWalletQaFailure('qa_event_publication_failed');
    }
  }

  Future<Map<String, Object?>> request(
    String eventName,
    Map<String, Object?> fields, {
    Duration timeout = const Duration(minutes: 15),
  }) async {
    _rejectReservedFields(fields);
    final id = '$runId-$role-${++_sequence}';
    await _publish(eventName, {'id': id, ...fields});
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final request = await _client.getUrl(_base.resolve('/commands/$id'));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await _body(response);
      if (response.statusCode == HttpStatus.notFound) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const FullWalletQaFailure('qa_command_read_failed');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['ok'] != true) {
        throw const FullWalletQaFailure('qa_command_rejected');
      }
      validatePublicFields(decoded);
      return decoded;
    }
    throw const FullWalletQaFailure('qa_command_timeout');
  }

  Future<void> preflight(WalletServiceConfiguration services) async {
    Future<Map<String, Object?>> probe(Uri uri, {String? method}) async {
      try {
        final request = method == null
            ? await _client.getUrl(uri)
            : await _client.postUrl(uri);
        request.followRedirects = false;
        if (method != null) {
          final payload = utf8.encode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 'aster-qa-preflight',
              'method': method,
              'params': <Object>[],
            }),
          );
          request.headers.contentType = ContentType.json;
          request.contentLength = payload.length;
          request.add(payload);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        final body = await _body(response).timeout(const Duration(seconds: 10));
        final result = <String, Object?>{'http_status': response.statusCode};
        if (method == null) {
          final value = body.trim();
          if (RegExp(r'^[0-9]{1,12}$').hasMatch(value)) {
            result['height'] = int.parse(value);
          } else if (RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
            result['block_hash'] = value;
          } else {
            result['unexpected_body'] = true;
          }
        } else {
          final value = jsonDecode(body);
          if (value is Map<String, Object?>) {
            result['result_present'] =
                value.containsKey('result') && value['error'] == null;
            final rpcError = value['error'];
            if (rpcError is Map && rpcError['code'] is int) {
              result['rpc_error_code'] = rpcError['code'];
            }
            if (method == 'eth_chainId') {
              final chain = value['result'];
              if (chain is String &&
                  RegExp(r'^0x[0-9a-fA-F]{1,12}$').hasMatch(chain)) {
                result['chain_id'] = int.parse(chain.substring(2), radix: 16);
              }
            }
          } else {
            result['unexpected_body'] = true;
          }
        }
        return result;
      } catch (error) {
        return {'failure_type': error.runtimeType.toString()};
      }
    }

    final indexer = Uri.parse(services.indexerUrl!);
    final basePath = indexer.path.replaceFirst(RegExp(r'/$'), '');
    final proxy = Uri.parse(services.rgbTransportProxy!);
    final checks = <String, Future<Map<String, Object?>>>{
      'esplora_tip': probe(
        indexer.replace(path: '$basePath/blocks/tip/height'),
      ),
      'esplora_genesis': probe(
        indexer.replace(path: '$basePath/block-height/0'),
      ),
      'rgb_proxy': probe(
        proxy.replace(scheme: proxy.scheme == 'rpcs' ? 'https' : 'http'),
        method: 'server.info',
      ),
      if (services.ethRpcUrl case final url?)
        'evm': probe(Uri.parse(url), method: 'eth_chainId'),
    };
    final results = <String, Object?>{};
    for (final check in checks.entries) {
      results[check.key] = await check.value;
    }
    await event('public_network_preflight', results);
  }

  void close() => _client.close(force: true);

  static Future<String> _body(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 64 * 1024) {
        throw const FullWalletQaFailure('qa_response_too_large');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  static void _rejectReservedFields(Map<String, Object?> fields) {
    if (fields.keys.any(
      const {'event', 'run_id', 'role', 'time_utc', 'id'}.contains,
    )) {
      throw const FullWalletQaFailure('qa_reserved_field_rejected');
    }
  }

  /// Validates the public coordination schema on outgoing and incoming data.
  static void validatePublicFields(Object? value) =>
      _validatePublicFields(value, const []);

  static void _validatePublicFields(Object? value, List<String> path) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FullWalletQaFailure('qa_private_field_rejected');
        }
        final next = [...path, key];
        if (RegExp(
              r'password|mnemonic|seed|secret|private.?key|token|cookie',
              caseSensitive: false,
            ).hasMatch(key) &&
            !_isPublicTokenAmount(next, entry.value)) {
          throw const FullWalletQaFailure('qa_private_field_rejected');
        }
        _validatePublicFields(entry.value, next);
      }
    } else if (value is List) {
      for (var index = 0; index < value.length; index += 1) {
        _validatePublicFields(value[index], [...path, '[$index]']);
      }
    } else if (value != null &&
        value is! String &&
        value is! num &&
        value is! bool) {
      throw const FullWalletQaFailure('qa_non_public_type_rejected');
    }
  }

  static bool _isPublicTokenAmount(List<String> path, Object? value) {
    final known =
        (path.length == 1 && path.single == 'evm_token_balance') ||
        (path.length == 2 && path[0] == 'mint' && path[1] == 'tokenCommission');
    if (!known ||
        value is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,77})$').hasMatch(value)) {
      return false;
    }
    return BigInt.parse(value) <= (BigInt.one << 256) - BigInt.one;
  }
}

/// Deliberately excludes causes and SDK exception messages from test output.
/// Codes are static application diagnostics; phrase material remains in memory.
final class FullWalletQaFailure implements Exception {
  const FullWalletQaFailure(this.code, [this.diagnostics = const []]);

  final String code;
  final List<Map<String, Object?>> diagnostics;

  @override
  String toString() => 'FullWalletQaFailure($code)';
}

T requireQaSuccess<T>(AppResult<T> result, String operation) {
  return switch (result) {
    AppSuccess<T>(:final value) => value,
    AppFailureResult<T>(:final failure) => throw qaAppFailure(
      operation,
      failure,
    ),
  };
}

FullWalletQaFailure qaAppFailure(String operation, AppFailure failure) {
  final diagnostics = <Map<String, Object?>>[];
  void visit(Object? cause, int depth) {
    if (depth > 8 || diagnostics.length >= 24) return;
    if (cause is AppFailure) {
      diagnostics.add({
        'code': cause.code,
        'kind': cause.kind.name,
        'requires_reconciliation': cause.requiresReconciliation,
        'outcome_unknown': cause.outcomeUnknown,
      });
      visit(cause.cause, depth + 1);
    } else if (cause is FailureDiagnostic) {
      diagnostics.add({
        'source_type': cause.sourceType,
        'source_code': cause.sourceCode,
        'status_code': cause.statusCode,
        'context': cause.context,
      });
    } else if (cause is List) {
      for (final item in cause.take(24)) {
        visit(item, depth + 1);
      }
    }
  }

  visit(failure, 0);
  return FullWalletQaFailure(
    '$operation:${failure.code}:${failure.kind.name}',
    diagnostics,
  );
}
