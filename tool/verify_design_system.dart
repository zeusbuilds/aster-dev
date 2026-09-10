import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

const _forbiddenUiConstructors = <String>{
  'BoxShadow',
  'ClipRRect',
  'Color',
  'LinearGradient',
  'OutlineInputBorder',
  'RadialGradient',
  'RoundedRectangleBorder',
  'SweepGradient',
  'TextStyle',
};

const _typographyArguments = <String>{
  'fontFamily',
  'fontSize',
  'fontWeight',
  'letterSpacing',
};

const _geometryArguments = <String>{
  'blurRadius',
  'borderRadius',
  'cacheExtent',
  'childAspectRatio',
  'endIndent',
  'height',
  'iconSize',
  'indent',
  'itemExtent',
  'mainAxisSpacing',
  'margin',
  'maxHeight',
  'maxWidth',
  'minHeight',
  'minWidth',
  'radius',
  'padding',
  'size',
  'spreadRadius',
  'strokeWidth',
  'thickness',
  'width',
};

const _rawGeometryConstructors = <String>{
  'BorderRadius',
  'EdgeInsets',
  'Radius',
};

/// Result of checking repository-owned UI against the design-system policy.
final class DesignSystemVerification {
  const DesignSystemVerification({
    required this.sourceCount,
    required this.failures,
  });

  /// Number of non-generated screen, page, and widget sources examined.
  final int sourceCount;

  /// Deterministically sorted parse or policy failures.
  final List<String> failures;

  /// Whether every examined source satisfies the policy.
  bool get passed => failures.isEmpty;
}

/// Verifies semantic design-system ownership for repository UI code.
void main() {
  final result = verifyDesignSystem(Directory.current);
  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Design-system policy verified across ${result.sourceCount} UI sources.',
  );
}

/// Checks the owned UI sources beneath [repositoryRoot].
///
/// Theme/token implementations and custom non-UI domain models are outside
/// this boundary. Screens, pages, and widgets must consume semantic roles;
/// painter coordinate math may remain local when it does not define a reusable
/// product measurement.
DesignSystemVerification verifyDesignSystem(Directory repositoryRoot) {
  final root = repositoryRoot.absolute;
  final sourceRoot = Directory('${root.path}/lib');
  if (!sourceRoot.existsSync()) {
    return const DesignSystemVerification(
      sourceCount: 0,
      failures: ['Missing lib directory. Run this tool from the repo root.'],
    );
  }

  final candidates =
      sourceRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _isOwnedDartSource(_relative(root, file)))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final failures = <String>[];
  final featureSet = FeatureSet.latestLanguageVersion();
  var sourceCount = 0;

  for (final source in candidates) {
    final sourcePath = _relative(root, source);
    final parsed = parseFile(
      path: source.path,
      featureSet: featureSet,
      throwIfDiagnostics: false,
    );
    if (!_isOwnedUiSource(sourcePath) && !_containsUiDeclaration(parsed.unit)) {
      continue;
    }
    sourceCount += 1;
    for (final error in parsed.errors) {
      final line = parsed.lineInfo.getLocation(error.offset).lineNumber;
      failures.add('$sourcePath:$line: parse error: ${error.message}');
    }

    parsed.unit.accept(
      _DesignSystemVisitor((node, message) {
        final line = parsed.lineInfo.getLocation(node.offset).lineNumber;
        failures.add('$sourcePath:$line: $message');
      }),
    );
  }

  return DesignSystemVerification(
    sourceCount: sourceCount,
    failures: List<String>.unmodifiable(failures.toSet().toList()..sort()),
  );
}

final class _DesignSystemVisitor extends RecursiveAstVisitor<void> {
  _DesignSystemVisitor(this._report);

  final void Function(AstNode node, String message) _report;
  var _coordinateMathDepth = 0;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass.name.lexeme;
    final ownsCoordinateMath =
        superclass == 'CustomPainter' ||
        superclass == 'MultiChildLayoutDelegate' ||
        superclass == 'SnapshotPainter';
    if (ownsCoordinateMath) _coordinateMathDepth += 1;
    super.visitClassDeclaration(node);
    if (ownsCoordinateMath) _coordinateMathDepth -= 1;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName =
        _knownConstructorName(node.constructorName.toSource()) ??
        node.constructorName.type.name.lexeme;
    if (_forbiddenUiConstructors.contains(typeName)) {
      _report(
        node,
        '$typeName must be supplied by a semantic design-system primitive.',
      );
    }

    if (_coordinateMathDepth == 0 &&
        _rawGeometryConstructors.contains(typeName) &&
        _containsDirectNonZeroMeasurement(node.argumentList)) {
      _report(
        node,
        '$typeName must use semantic spacing or radius values, not a raw '
        'measurement.',
      );
    }

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    final targetName = node.target?.toSource().split('.').last;
    if (node.target == null && _forbiddenUiConstructors.contains(methodName)) {
      _report(
        node,
        '$methodName must be supplied by a semantic design-system primitive.',
      );
    }
    if (targetName == 'Color' && methodName != 'lerp') {
      _report(
        node,
        'Color must be supplied by a semantic design-system primitive.',
      );
    }
    if (_coordinateMathDepth == 0 &&
        targetName != null &&
        _rawGeometryConstructors.contains(targetName) &&
        _containsDirectNonZeroMeasurement(node.argumentList)) {
      _report(
        node,
        '$targetName must use semantic spacing or radius values, not a raw '
        'measurement.',
      );
    }
    if (methodName == 'withOpacity') {
      _report(
        node,
        'withOpacity is forbidden; use a semantic state-layer or effect role.',
      );
    }
    if (methodName == 'withValues') {
      final alpha = _namedArgument(node.argumentList, 'alpha');
      if (alpha != null && _containsNumericLiteral(alpha.argumentExpression)) {
        _report(
          alpha,
          'A raw alpha is forbidden; use a semantic state-layer or effect '
          'role.',
        );
      }
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final name = node.name.lexeme;
    if (name == 'splashFactory' || name == 'splashColor') {
      _report(
        node,
        'Tap ink policy belongs to AppTheme, not a local splash override.',
      );
    }
    if (_typographyArguments.contains(name)) {
      _report(
        node,
        '$name must come from an AsterTypeRoles style, not a local override.',
      );
    }
    if (_coordinateMathDepth == 0 &&
        _geometryArguments.contains(name) &&
        _isDirectNonZeroMeasurement(node.argumentExpression)) {
      _report(
        node,
        '$name must use spacing, iconography, stroke, radius, component, or '
        'art tokens instead of a raw measurement.',
      );
    }
    if ((name == 'opacity' ||
            name == 'duration' ||
            name == 'reverseDuration') &&
        _containsNumericLiteral(node.argumentExpression)) {
      _report(
        node,
        '$name must use a semantic effect, state-layer, or motion role.',
      );
    }

    super.visitNamedArgument(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    final name = node.name.lexeme.toLowerCase();
    if (_coordinateMathDepth == 0 &&
        initializer != null &&
        (name == 'opacity' || name == 'alpha') &&
        _containsNumericLiteral(initializer)) {
      _report(
        node,
        'Local $name values must use semantic effect or state-layer roles.',
      );
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    final identifier = node.identifier.name;
    if (prefix == 'Colors') {
      _report(
        node,
        'Colors.* is forbidden; use ColorScheme or AsterColors semantics.',
      );
    }
    _checkProperty(node, prefix, identifier);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target?.toSource();
    final identifier = node.propertyName.name;
    if (target == 'Colors') {
      _report(
        node,
        'Colors.* is forbidden; use ColorScheme or AsterColors semantics.',
      );
    }
    _checkProperty(node, target, identifier);
    super.visitPropertyAccess(node);
  }

  void _checkProperty(AstNode node, String? target, String identifier) {
    if (identifier == 'textTheme') {
      _report(
        node,
        'Feature UI must use AsterTypeRoles instead of TextTheme directly.',
      );
    }
    if (target == 'context' &&
        (identifier == 'colors' || identifier == 'radius')) {
      _report(
        node,
        'Deprecated context.$identifier token access is forbidden.',
      );
    }
    if ((target == 'spacing' && _spacingPrimitive.hasMatch(identifier)) ||
        (target == 'radius' && _radiusPrimitive.hasMatch(identifier))) {
      _report(node, 'Primitive token access $target.$identifier is forbidden.');
    }
    if (target == 'Curves') {
      _report(node, 'Curves.* must be replaced by a semantic motion curve.');
    }
  }
}

final _spacingPrimitive = RegExp(r'^spacing\d+$');
final _radiusPrimitive = RegExp(r'^radius\d+$');

String? _knownConstructorName(String source) {
  for (final segment in source.split('.')) {
    if (_forbiddenUiConstructors.contains(segment) ||
        _rawGeometryConstructors.contains(segment)) {
      return segment;
    }
  }
  return null;
}

NamedArgument? _namedArgument(ArgumentList arguments, String name) {
  for (final argument in arguments.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument;
    }
  }
  return null;
}

bool _containsNumericLiteral(AstNode node) {
  final collector = _NumericLiteralCollector();
  node.accept(collector);
  return collector.hasLiteral;
}

bool _containsDirectNonZeroMeasurement(ArgumentList arguments) {
  return arguments.arguments.any((argument) {
    if (argument is NamedArgument) {
      return _isDirectNonZeroMeasurement(argument.argumentExpression);
    }
    return argument is Expression && _isDirectNonZeroMeasurement(argument);
  });
}

bool _isDirectNonZeroMeasurement(Expression expression) {
  return switch (expression) {
    DoubleLiteral() => expression.value != 0,
    IntegerLiteral() => expression.value != 0,
    ParenthesizedExpression() => _isDirectNonZeroMeasurement(
      expression.expression,
    ),
    PrefixExpression() => _isDirectNonZeroMeasurement(expression.operand),
    ConditionalExpression() =>
      _isDirectNonZeroMeasurement(expression.thenExpression) ||
          _isDirectNonZeroMeasurement(expression.elseExpression),
    _ => false,
  };
}

final class _NumericLiteralCollector extends RecursiveAstVisitor<void> {
  bool hasLiteral = false;

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    hasLiteral = true;
  }

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    hasLiteral = true;
  }
}

bool _isOwnedUiSource(String path) {
  if (path.startsWith('lib/shared/widgets/') ||
      path.startsWith('lib/shared/screens/')) {
    return true;
  }
  if (!path.startsWith('lib/features/')) return false;
  return path.contains('/presentation/screens/') ||
      path.contains('/presentation/widgets/') ||
      path.contains('/presentation/pages/');
}

bool _isOwnedDartSource(String path) {
  return path.endsWith('.dart') &&
      !path.endsWith('.g.dart') &&
      !path.endsWith('.freezed.dart');
}

bool _containsUiDeclaration(CompilationUnit unit) {
  final collector = _UiDeclarationCollector();
  unit.accept(collector);
  return collector.found;
}

const _uiSuperclasses = <String>{
  'ConsumerStatefulWidget',
  'ConsumerWidget',
  'CustomPainter',
  'InheritedWidget',
  'MultiChildLayoutDelegate',
  'SingleChildRenderObjectWidget',
  'SnapshotPainter',
  'StatefulWidget',
  'StatelessWidget',
};

final class _UiDeclarationCollector extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_uiSuperclasses.contains(node.extendsClause?.superclass.name.lexeme)) {
      found = true;
      return;
    }
    super.visitClassDeclaration(node);
  }
}

String _relative(Directory root, File file) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return file.absolute.path
      .substring(prefix.length)
      .replaceAll(Platform.pathSeparator, '/');
}
