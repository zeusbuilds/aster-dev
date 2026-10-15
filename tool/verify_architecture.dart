import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const _infrastructureOwners = <String, Set<String>>{
  'flutter_secure_storage': {'lib/core/storage/secure_storage_service.dart'},
  'haptic_feedback': {'lib/shared/feedback/haptic_feedback_service.dart'},
  // The EVM adapter performs one non-retrying, bounded eth_chainId POST;
  // ResilientHttpClient owns the separate GET-with-retry policy.
  'http': {
    'lib/core/network/http_evm_chain_validator.dart',
    'lib/core/network/resilient_http_client.dart',
  },
  'image_picker': {'lib/features/scan/data/services/mobile_scan_adapters.dart'},
  'mobile_scanner': {
    'lib/features/scan/data/services/mobile_scan_adapters.dart',
  },
  'package_info_plus': {'lib/core/platform/app_metadata_service.dart'},
  'path_provider': {'lib/core/di/providers.dart'},
  'share_plus': {'lib/core/platform/share_service.dart'},
  'shared_preferences': {
    'lib/core/bootstrap/app_bootstrap.dart',
    'lib/core/di/providers.dart',
    'lib/core/storage/preferences_service.dart',
    'lib/main.dart',
  },
  'url_launcher': {'lib/core/platform/external_uri_service.dart'},
};

const _sdkOwners = {
  'lib/core/errors/failure_mapper.dart',
  'lib/features/wallet/data/runtime/rgb_wallet_activity_mapper.dart',
  'lib/features/wallet/data/runtime/rgb_wallet_balance_mapper.dart',
  'lib/features/wallet/data/runtime/rgb_wallet_engine.dart',
  'lib/features/wallet/data/runtime/rgb_wallet_native_value_parser.dart',
};

const _implementationConsumers = <String, Set<String>>{
  'lib/features/scan/data/services/scan_lifecycle_surface.dart': {
    'lib/features/scan/data/services/scan_session.dart',
  },
  'lib/features/scan/data/services/scan_session.dart': {
    'lib/features/scan/data/services/mobile_scan_adapters.dart',
  },
  'lib/features/wallet/data/runtime/rgb_wallet_activity_mapper.dart': {
    'lib/features/wallet/data/runtime/rgb_wallet_engine.dart',
  },
  'lib/features/wallet/data/runtime/rgb_wallet_balance_mapper.dart': {
    'lib/features/wallet/data/runtime/rgb_wallet_engine.dart',
  },
  'lib/features/wallet/data/runtime/rgb_wallet_native_value_parser.dart': {
    'lib/features/wallet/data/runtime/rgb_wallet_activity_mapper.dart',
    'lib/features/wallet/data/runtime/rgb_wallet_balance_mapper.dart',
    'lib/features/wallet/data/runtime/rgb_wallet_engine.dart',
  },
  'lib/features/wallet/data/repository/wallet_payment_operations.dart': {
    'lib/features/wallet/data/repository/wallet_repository.dart',
  },
};

const _presentationInfrastructureProviders = <String>{
  'appMetadataServiceProvider',
  'clipboardServiceProvider',
  'externalUriServiceProvider',
  'preferencesServiceProvider',
  'resilientHttpClientProvider',
  'secureStorageServiceProvider',
  'sensitiveClipboardServiceProvider',
  'shareServiceProvider',
  'sharedPreferencesProvider',
  'walletDirectoryManagerProvider',
  'walletRegistryDocumentStoreProvider',
  'walletSecretStoreProvider',
  'walletStorageSecurityProvider',
};

/// Result of checking one repository tree against the architecture policy.
final class ArchitectureVerification {
  const ArchitectureVerification({
    required this.sourceCount,
    required this.importCount,
    required this.exportCount,
    required this.failures,
  });

  /// Number of non-generated Dart files examined under `lib/`.
  final int sourceCount;

  /// Number of import URIs examined, including conditional alternatives.
  final int importCount;

  /// Number of export URIs examined, including conditional alternatives.
  final int exportCount;

  /// Deterministically sorted policy or parse failures.
  final List<String> failures;

  /// Whether every examined source satisfies the policy.
  bool get passed => failures.isEmpty;
}

/// Verifies dependency direction and infrastructure-adapter ownership.
void main() {
  final result = verifyArchitecture(Directory.current);
  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Architecture policy verified across ${result.sourceCount} Dart sources '
    'and ${result.importCount} imports / ${result.exportCount} exports.',
  );
}

/// Checks the owned Dart sources beneath [repositoryRoot].
///
/// This function does not mutate global process state, which allows the same
/// release policy to be fault-tested against isolated repository fixtures.
ArchitectureVerification verifyArchitecture(Directory repositoryRoot) {
  final root = repositoryRoot.absolute;
  final sourceRoot = Directory('${root.path}/lib');
  if (!sourceRoot.existsSync()) {
    return const ArchitectureVerification(
      sourceCount: 0,
      importCount: 0,
      exportCount: 0,
      failures: ['Missing lib directory. Run this tool from the repo root.'],
    );
  }

  final sources =
      sourceRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _isOwnedDartSource(file.path))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final failures = <String>[];
  final featureSet = FeatureSet.latestLanguageVersion();
  var importCount = 0;
  var exportCount = 0;

  for (final source in sources) {
    final sourcePath = _relative(root, source);
    final parsed = parseFile(
      path: source.path,
      featureSet: featureSet,
      throwIfDiagnostics: false,
    );
    for (final error in parsed.errors) {
      final line = parsed.lineInfo.getLocation(error.offset).lineNumber;
      failures.add('$sourcePath:$line: parse error: ${error.message}');
    }
    for (final dependency in _dependencyUris(parsed.unit)) {
      final uri = dependency.uri;
      if (dependency.isExport) {
        exportCount += 1;
      } else {
        importCount += 1;
      }
      final line = parsed.lineInfo.getLocation(dependency.offset).lineNumber;
      final package = _packageName(uri);

      if (package == 'rgb_sdk_flutter' && !_sdkOwners.contains(sourcePath)) {
        failures.add(
          '$sourcePath:$line: rgb_sdk_flutter may be imported only by the '
          'wallet adapter or SDK failure mapper.',
        );
      }

      final infrastructureOwners = _infrastructureOwners[package];
      if (infrastructureOwners != null &&
          !infrastructureOwners.contains(sourcePath)) {
        failures.add(
          '$sourcePath:$line: package:$package is infrastructure and must be '
          'imported only by its approved adapter/composition owner.',
        );
      }

      final targetPath = _repositoryTarget(root, source, uri);
      if (targetPath == null) continue;
      final implementationConsumers = _implementationConsumers[targetPath];
      if (implementationConsumers != null &&
          !implementationConsumers.contains(sourcePath)) {
        failures.add(
          '$sourcePath:$line: implementation-only $targetPath may be '
          'imported only by its owning adapter.',
        );
      }
      if (_isFeatureDomain(sourcePath) &&
          (_isFeatureData(targetPath) || _isFeaturePresentation(targetPath))) {
        failures.add(
          '$sourcePath:$line: domain code must not depend on $targetPath.',
        );
      }
      if (_isFeatureData(sourcePath) && _isFeaturePresentation(targetPath)) {
        failures.add(
          '$sourcePath:$line: data code must not depend on presentation '
          '$targetPath.',
        );
      }
      if (_isFeaturePresentation(sourcePath) &&
          !_isViewModel(sourcePath) &&
          _isFeatureData(targetPath)) {
        failures.add(
          '$sourcePath:$line: presentation outside a ViewModel must consume '
          'domain/presentation contracts, not data implementation $targetPath.',
        );
      }
    }

    if (_isFeaturePresentation(sourcePath) && !_isViewModel(sourcePath)) {
      final identifiers = <String>{};
      parsed.unit.accept(_SimpleIdentifierCollector(identifiers));
      final forbidden =
          identifiers
              .where(
                (name) =>
                    _presentationInfrastructureProviders.contains(name) ||
                    name.endsWith('RepositoryProvider'),
              )
              .toList()
            ..sort();
      for (final name in forbidden) {
        failures.add(
          '$sourcePath: feature presentation must send $name intent through '
          'a ViewModel rather than access infrastructure directly.',
        );
      }
    }

    if (_isFeaturePresentation(sourcePath)) {
      final diagnosticOutcomeReferences = <SimpleIdentifier>[];
      final syntheticStacks = <MethodInvocation>[];
      final discardedExceptions = <CatchClause>[];
      parsed.unit.accept(
        _NamedIdentifierCollector(
          'outcomeUnknown',
          diagnosticOutcomeReferences,
        ),
      );
      parsed.unit.accept(_SyntheticFailureStackCollector(syntheticStacks));
      parsed.unit.accept(
        _DiscardedPresentationExceptionCollector(discardedExceptions),
      );
      for (final reference in diagnosticOutcomeReferences) {
        final line = parsed.lineInfo.getLocation(reference.offset).lineNumber;
        failures.add(
          '$sourcePath:$line: feature presentation must use '
          'requiresReconciliation rather than branch on the diagnostic '
          'outcomeUnknown subset.',
        );
      }
      for (final invocation in syntheticStacks) {
        final line = parsed.lineInfo.getLocation(invocation.offset).lineNumber;
        failures.add(
          '$sourcePath:$line: feature presentation must pass the captured '
          'failure stack instead of replacing it with StackTrace.current.',
        );
      }
      for (final clause in discardedExceptions) {
        final line = parsed.lineInfo.getLocation(clause.offset).lineNumber;
        failures.add(
          '$sourcePath:$line: feature presentation must capture and map '
          'thrown exceptions instead of discarding them with catch (_).',
        );
      }
    }

    for (final declaration
        in parsed.unit.declarations.whereType<ClassDeclaration>()) {
      final className = declaration.namePart.typeName.lexeme;
      final isOwnedState =
          className.endsWith('State') &&
          (_isPresentationModel(sourcePath) ||
              _hasImmutableAnnotation(declaration));
      if (!isOwnedState) continue;
      final methods = declaration.body.members.whereType<MethodDeclaration>();
      final hasEquality = methods.any(
        (method) => method.isOperator && method.name.lexeme == '==',
      );
      final hasHashCode = methods.any(
        (method) => method.isGetter && method.name.lexeme == 'hashCode',
      );
      if (hasEquality && hasHashCode) continue;

      final missing = <String>[
        if (!hasEquality) 'operator ==',
        if (!hasHashCode) 'hashCode',
      ].join(' and ');
      final line = parsed.lineInfo
          .getLocation(declaration.namePart.typeName.offset)
          .lineNumber;
      failures.add(
        '$sourcePath:$line: app state $className must declare $missing so '
        'Riverpod and other listeners can suppress equal publications.',
      );
    }
  }

  return ArchitectureVerification(
    sourceCount: sources.length,
    importCount: importCount,
    exportCount: exportCount,
    failures: List<String>.unmodifiable(failures..sort()),
  );
}

Iterable<_DependencyUri> _dependencyUris(CompilationUnit unit) sync* {
  for (final directive in unit.directives) {
    switch (directive) {
      case ImportDirective():
        final uri = directive.uri.stringValue;
        if (uri != null) {
          yield _DependencyUri(
            uri: uri,
            offset: directive.uri.offset,
            isExport: false,
          );
        }
        for (final configuration in directive.configurations) {
          final configuredUri = configuration.uri.stringValue;
          if (configuredUri != null) {
            yield _DependencyUri(
              uri: configuredUri,
              offset: configuration.uri.offset,
              isExport: false,
            );
          }
        }
      case ExportDirective():
        final uri = directive.uri.stringValue;
        if (uri != null) {
          yield _DependencyUri(
            uri: uri,
            offset: directive.uri.offset,
            isExport: true,
          );
        }
        for (final configuration in directive.configurations) {
          final configuredUri = configuration.uri.stringValue;
          if (configuredUri != null) {
            yield _DependencyUri(
              uri: configuredUri,
              offset: configuration.uri.offset,
              isExport: true,
            );
          }
        }
      default:
        break;
    }
  }
}

String? _repositoryTarget(Directory root, File source, String uri) {
  if (uri.startsWith('package:aster/')) {
    return 'lib/${uri.substring('package:aster/'.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;
  final target = File.fromUri(source.parent.uri.resolve(uri));
  if (!target.absolute.path.startsWith('${root.path}/lib/')) return null;
  return _relative(root, target);
}

String? _packageName(String uri) {
  if (!uri.startsWith('package:')) return null;
  final path = uri.substring('package:'.length);
  return path.split('/').firstOrNull;
}

bool _isFeatureDomain(String path) =>
    path.startsWith('lib/features/') && path.contains('/domain/');

bool _isFeatureData(String path) =>
    path.startsWith('lib/features/') && path.contains('/data/');

bool _isFeaturePresentation(String path) =>
    path.startsWith('lib/features/') && path.contains('/presentation/');

bool _isPresentationModel(String path) =>
    _isFeaturePresentation(path) && path.contains('/presentation/models/');

bool _hasImmutableAnnotation(ClassDeclaration declaration) {
  return declaration.metadata.any((annotation) {
    final name = annotation.name.toSource();
    return name == 'immutable' || name.endsWith('.immutable');
  });
}

bool _isViewModel(String path) => path.contains('/presentation/view_model/');

bool _isOwnedDartSource(String path) =>
    path.endsWith('.dart') &&
    !path.endsWith('.g.dart') &&
    !path.endsWith('.freezed.dart') &&
    !path.endsWith('.mocks.dart');

String _relative(Directory root, File file) =>
    file.absolute.path.substring(root.path.length + 1);

final class _DependencyUri {
  const _DependencyUri({
    required this.uri,
    required this.offset,
    required this.isExport,
  });

  final String uri;
  final int offset;
  final bool isExport;
}

final class _SimpleIdentifierCollector extends RecursiveAstVisitor<void> {
  _SimpleIdentifierCollector(this.names);

  final Set<String> names;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

final class _NamedIdentifierCollector extends RecursiveAstVisitor<void> {
  _NamedIdentifierCollector(this.name, this.references);

  final String name;
  final List<SimpleIdentifier> references;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name) references.add(node);
    super.visitSimpleIdentifier(node);
  }
}

final class _SyntheticFailureStackCollector extends RecursiveAstVisitor<void> {
  _SyntheticFailureStackCollector(this.invocations);

  final List<MethodInvocation> invocations;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = node.argumentList.arguments;
    if (node.target?.toSource() == 'FailureMapper' &&
        node.methodName.name == 'from' &&
        arguments.length >= 2 &&
        arguments[1].toSource() == 'StackTrace.current') {
      invocations.add(node);
    }
    super.visitMethodInvocation(node);
  }
}

final class _DiscardedPresentationExceptionCollector
    extends RecursiveAstVisitor<void> {
  _DiscardedPresentationExceptionCollector(this.clauses);

  final List<CatchClause> clauses;

  @override
  void visitCatchClause(CatchClause node) {
    if (node.exceptionParameter?.name.lexeme == '_') clauses.add(node);
    super.visitCatchClause(node);
  }
}
