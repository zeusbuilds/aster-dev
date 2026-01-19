# Google-Style Architecture Summary

**Note**: This architecture uses a **simplified MVVM pattern** that maintains separation of concerns and testability without over-engineering. We skip use cases and entities in favor of a simpler structure: **Models → Repository → ViewModel → View**.

**Key Technologies**:
- **Riverpod** (not hooks_riverpod) with **@riverpod annotations** for code generation
- **Chopper** for type-safe API services with code generation
- **ConsumerWidget/ConsumerStatefulWidget** (no hooks, use initState instead)

## Quick Reference Guide

### 1. Architecture Pattern (Simplified)
- **MVVM + Riverpod** with clear layer separation
- **Unidirectional data flow**: State down, events up
- **Simple Architecture**: Models → Repository → ViewModel → View
- **No Use Cases or Entities**: Business logic in ViewModel or Repository

### 2. Folder Structure (Simplified)
```
lib/
├── core/              # Infrastructure (network, storage, errors, DI)
├── features/           # Feature modules (models/repository/viewmodels/pages/widgets)
│   └── wallet/
│       ├── models/     # Data models (Freezed)
│       ├── repository/ # Data access (handles all data sources)
│       ├── viewmodels/ # Business logic & state
│       ├── providers/  # Riverpod providers
│       ├── pages/      # Screen widgets
│       └── widgets/    # Feature-specific widgets
├── shared/            # Shared UI components and theme
└── platform/          # Native/FFI code isolation
```

### 3. Theming
- **Design tokens** (colors, spacing, typography)
- **Theme variants** (light, dark, system, custom)
- **Dynamic theming** with runtime switching
- **Accessibility** support (high contrast, text scaling)

### 4. Routing
- **Type-safe routing** with enums/classes
- **Route guards** (auth, onboarding, feature flags)
- **Nested routing** with shell routes
- **Deep linking** with parameter validation
- **Route analytics** for navigation tracking

### 5. API Layer (Chopper)
- **Chopper services**: Type-safe API services with code generation
- **Interceptor chain**: Auth, logging, error handling
- **Error handling**: Consistent error mapping
- **Request/Response models**: Type-safe models with JSON serialization
- **Code generation**: Chopper generates service implementations
- **Riverpod annotations**: Providers generated with @riverpod

### 6. Data Layer (Simplified)
- **Repository pattern**: Single repository handles all data sources internally
- **Chopper API services**: Type-safe API calls via Chopper services
- **Remote → Local → GDK** fallback strategy (all in repository)
- **Offline-first** architecture
- **Cache-first** with network fallback
- **No separate data source classes**: Repository methods handle API/DB/GDK directly

### 7. Rust/Native Integration
- **Service abstraction** layer for FFI calls
- **Isolated in platform/** directory
- **Type-safe** interfaces
- **Mockable** for testing

### 8. MVVM Implementation (Simplified)
- **ViewModels** use @riverpod class (generated StateNotifier)
- **Freezed state** classes
- **Direct Repository access**: ViewModel calls Repository directly (no use cases)
- **Business logic** in ViewModel or Repository
- **Widgets** use ConsumerWidget/ConsumerStatefulWidget (no hooks)
- **Riverpod annotations**: @riverpod for code generation

### 9. Testing (Simplified)
- **Unit tests**: ViewModels, Repositories
- **Widget tests**: UI components, interactions
- **Integration tests**: End-to-end flows
- **Golden tests**: UI regression (optional)
- **Performance tests**: Benchmark critical paths (optional)

### 10. Dependency Injection (Riverpod Annotations)
- **Centralized DI** in core/di/
- **@riverpod annotations**: Code-generated providers
- **Provider-based** injection with type safety
- **Lazy initialization**
- **Test overrides** support

### 11. Error Handling
- **Failure classes** (ServerFailure, NetworkFailure, etc.)
- **Either pattern** (Result<T> = Either<Failure, T>)
- **Consistent error mapping**
- **User-friendly error messages**

### 12. Performance
- **Lazy loading** of data
- **Aggressive caching**
- **Code splitting** by feature
- **Image optimization** (cached network images)
- **List optimization** (ListView.builder with keys)
- **Isolate usage** for heavy computations

### 13. Security
- **Secure storage** for sensitive data
- **Certificate pinning** for API calls
- **Biometric authentication**
- **Data encryption** at rest
- **Secure key management**
- **Code obfuscation** in release builds

### 14. Monitoring
- **Error tracking** (Crashlytics)
- **Performance monitoring**
- **Analytics** (user behavior)
- **Structured logging**
- **Remote config** (feature flags, A/B testing)

### 15. Build & CI/CD
- **Flavors**: dev, staging, production
- **Code generation**: Freezed, json_serializable, chopper_generator, riverpod_generator
- **Strict linting**
- **Automated formatting**
- **CI/CD pipeline** with automated testing

---

## Key Principles (Simplified)

1. **Separation of Concerns**: Each layer has a single responsibility
2. **Dependency Inversion**: Depend on abstractions (Repository interface), not implementations
3. **Testability**: Every layer independently testable (mock Repository for ViewModel tests)
4. **Simplicity**: Models → Repository → ViewModel → View (no use cases or entities)
5. **Scalability**: Feature-based architecture for growth
6. **Type Safety**: Strong typing throughout with Freezed models
7. **Error Handling**: Consistent error handling patterns with Either
8. **Performance**: Optimized for large-scale apps
9. **Security**: Enterprise-grade security measures

---

## Migration Checklist

- [ ] Refactor core infrastructure (network, storage, DI)
- [ ] Migrate one feature to new architecture (wallet)
- [ ] Migrate remaining features incrementally
- [ ] Add comprehensive testing
- [ ] Performance optimization and monitoring

---

## File Structure Example (Simplified)

### Feature Module Structure
```
features/wallet/
├── models/                # Data models (Freezed, JSON serializable)
├── repository/            # Repository (handles all data sources)
├── viewmodels/            # ViewModels (StateNotifier)
├── providers/             # Riverpod providers
├── pages/                 # Screen widgets
└── widgets/               # Feature-specific widgets
```

---

## Code Examples (Simplified)

### ViewModel Pattern (Riverpod Annotations)
```dart
// features/wallet/providers/wallet_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'wallet_providers.g.dart';

@freezed
class WalletState with _$WalletState {
  const factory WalletState({
    @Default(false) bool isLoading,
    WalletModel? wallet,
    String? errorMessage,
  }) = _WalletState;
}

@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  WalletState build() => const WalletState();
  
  Future<void> loadWallet() async {
    state = state.copyWith(isLoading: true);
    final repository = ref.read(walletRepositoryProvider);
    final result = await repository.getWallet();
    result.fold(
      (failure) => state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      ),
      (wallet) => state = state.copyWith(
        isLoading: false,
        wallet: wallet,
      ),
    );
  }
}
```

### Repository Pattern (Simplified with Chopper)
```dart
abstract class WalletRepository {
  Future<Either<Failure, WalletModel>> getWallet();
}

class WalletRepositoryImpl implements WalletRepository {
  final WalletApiService _apiService;  // Chopper API service
  final Isar _isar;                    // For local DB
  final GdkService _gdkService;         // For native GDK
  final NetworkInfo _networkInfo;
  
  @override
  Future<Either<Failure, WalletModel>> getWallet() async {
    try {
      // Try local cache first
      final cached = await _isar.walletModels.where().findFirst();
      if (cached != null) return Right(cached);
      
      // If online, fetch from API
      if (await _networkInfo.isConnected) {
        final response = await _apiService.getWallet();
        if (response.isSuccessful && response.body != null) {
          final wallet = response.body!;
          await _isar.writeTxn(() => _isar.walletModels.put(wallet));
          return Right(wallet);
        }
        return Left(ServerFailure(message: 'Failed to fetch wallet'));
      }
      
      // Fallback to GDK (native)
      final gdkWallet = await _gdkService.getWallet();
      return Right(WalletModel.fromGdk(gdkWallet));
    } catch (e) {
      return Left(ServerFailure(message: e.toString()));
    }
  }
}

// Chopper API Service
@ChopperApi(baseUrl: '/api/v1/wallet')
abstract class WalletApiService extends ChopperService {
  @Get(path: '/')
  Future<Response<WalletModel>> getWallet();
}
```

---

## Best Practices

1. **Never pass Ref to services** - Inject concrete dependencies
2. **Use @riverpod annotations** - Code-generated providers for type safety
3. **Use Freezed for state** - Immutable state classes
4. **Use Chopper for API** - Type-safe API services with code generation
5. **Use ConsumerWidget/ConsumerStatefulWidget** - No hooks_riverpod
6. **Use initState** - Instead of useEffect for initialization
7. **Const widgets** - Where possible for performance
8. **Private widgets** - Instead of widget-building methods
9. **Use AsyncValue** - For loading/error states
10. **Test everything** - Unit, widget, integration tests
11. **Document complex logic** - Non-obvious decisions
12. **Follow SOLID principles** - Single responsibility, etc.
13. **Keep it simple** - Don't over-engineer

