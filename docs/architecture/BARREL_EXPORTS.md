# Barrel Export Policy

Barrels define import boundaries; they are not convenience files for every
directory traversal. The executable policy is
`dart run tool/verify_barrel_exports.dart`.

## Rules

1. A barrel is any repository Dart file with an `export` directive.
2. Its filename matches its directory: `models/models.dart`,
   `widgets/widgets.dart`, `repository/repository.dart`, and so on.
   The `view_model` directory uses `view_models.dart`.
3. Exports are relative, unique, and sorted by URI.
4. Generated files, private files, missing files, and package/Dart SDK URIs are
   never exported.
5. A source file does not import its own directory barrel. Import the sibling
   source directly to keep dependencies visible and avoid cycles.
6. Higher-level aggregate barrels may export lower-level boundary barrels, but
   the complete export graph must remain acyclic.
7. Barrels expose intended public contracts only. Native DTOs, persistence
   documents, generated providers, and private implementation helpers stay
   behind their owning adapter or repository.

## Usage

Across a feature or layer boundary, import the narrowest useful barrel:

```dart
import '../../domain/models/models.dart';
import '../view_model/view_models.dart';
```

Within the same directory, import the concrete sibling:

```dart
import 'wallet_amount.dart';
```

Do not create an app-wide feature barrel. `core/core.dart` and
`shared/shared.dart` are deliberate infrastructure/presentation boundaries;
feature dependencies remain explicit.

Run the policy locally with:

```sh
make verify-barrels
```
