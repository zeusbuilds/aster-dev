# Barrel Export Policy

Barrel files are boundary files. They make imports cleaner across folders, but
they should not hide dependencies inside the same folder.

## Rules

Use a barrel when importing across a folder boundary:

```dart
import '../widgets/widgets.dart';
import '../../../../shared/shared.dart';
```

Do not import a barrel from a file in the same folder:

```dart
// Avoid inside presentation/widgets
import 'widgets.dart';

// Prefer
import 'asset_row.dart';
```

Do not import an aggregate barrel from inside the package it aggregates. For
example, files in `lib/shared/widgets` should not import `../shared.dart`;
they should import the specific shared layer they need:

```dart
import '../theme/theme.dart';
```

Generated files are not exported from barrels. Source files own their generated
parts with `part` directives.

## Folder Pattern

- `shared.dart` exports stable shared APIs only: routing, screens, theme,
  models, and widgets.
- `core.dart` exports stable app infrastructure only: constants, errors,
  network, storage, utils, and DI.
- `widgets.dart` exports public widgets in that folder.
- `screens.dart` exports route-facing screens in that folder.
- `pages.dart` exports route-facing pages when the feature uses `pages/`
  instead of `screens/`.
- `models.dart`, `repository.dart`, `providers.dart`, and `viewmodels.dart`
  export public files for that layer.
- `tokens.dart` exports design-token extensions.

Barrels should be small, sorted by local dependency order, and limited to files
that are meant to be used by another folder. If a file is purely private to one
implementation, keep it out of the barrel.

## Import Direction

Feature screens may import their feature widget barrel. Feature widgets should
import sibling widgets directly when they compose each other.

Shared widgets may import `../theme/theme.dart` and direct sibling shared
widgets. They should not import `../shared.dart`, because that creates a broad
dependency on routing, models, screens, theme, and widgets.

Router configuration may import feature `screens.dart` or `pages.dart` barrels.
It should not import widget barrels.
