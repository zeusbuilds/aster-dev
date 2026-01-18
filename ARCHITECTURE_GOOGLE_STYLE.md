# Google-Style Architecture for Aster Wallet

## Executive Summary

This document outlines how a big tech company like Google would architect the Aster Bitcoin & Layer 2 Wallet app, focusing on scalability, maintainability, testability, and enterprise-grade patterns.

**Note**: This architecture uses a **simplified MVVM pattern** that maintains separation of concerns and testability without over-engineering. We skip use cases and entities in favor of a simpler structure: Models → Repository → ViewModel → View.

**Key Technologies**:
- **Riverpod** (not hooks_riverpod) with **@riverpod annotations** for code generation
- **Chopper** for type-safe API services with code generation
- **ConsumerWidget/ConsumerStatefulWidget** (no hooks, use initState instead)

---

## 1. Overall Architecture Pattern

### 1.1 MVVM + Riverpod Architecture (Simplified)

**Current State**: Mix of providers, some services, basic separation
**Google Approach**: Simplified MVVM with clear boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                        Presentation Layer                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Widgets    │  │   ViewModels │  │   Providers  │     │
│  │  (UI Only)   │←→│  (Business    │←→│  (State      │     │
│  │              │  │   Logic)     │  │   Management)│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│                         Data Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Models      │  │  Repository  │  │   Data       │     │
│  │  (Freezed)   │  │  (Handles    │  │   Sources    │     │
│  │              │  │   all data)  │  │   (API/DB)   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│                      Platform Layer                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Rust FFI    │  │  Native      │  │   System     │     │
│  │  (Boltz)     │  │  (GDK)       │  │   Services   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Key Principles

1. **Unidirectional Data Flow**: State flows down, events flow up
2. **Single Source of Truth**: All state in Riverpod providers
3. **Riverpod Annotations**: Use @riverpod for code-generated providers (no hooks_riverpod)
4. **Chopper for API**: Type-safe API services with code generation
5. **Dependency Inversion**: Depend on abstractions (Repository interface), not implementations
6. **Simple Architecture**: Models → Repository → ViewModel → View (no use cases or entities)
7. **Testability**: Every layer independently testable (mock Repository for ViewModel tests)

---

## 2. Folder Architecture

### 2.1 Proposed Structure

```
lib/
├── core/                           # Core functionality, shared across features
│   ├── constants/
│   │   ├── app_constants.dart
│   │   ├── api_endpoints.dart
│   │   └── storage_keys.dart
│   ├── errors/
│   │   ├── exceptions.dart
│   │   ├── failures.dart
│   │   └── error_handler.dart
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── interceptors/
│   │   │   ├── auth_interceptor.dart
│   │   │   ├── logging_interceptor.dart
│   │   │   └── error_interceptor.dart
│   │   └── network_info.dart
│   ├── storage/
│   │   ├── secure_storage_service.dart
│   │   ├── preferences_service.dart
│   │   └── database_service.dart
│   ├── utils/
│   │   ├── validators.dart
│   │   ├── formatters.dart
│   │   └── extensions/
│   └── di/                         # Dependency Injection
│       ├── providers.dart
│       └── modules/
│           ├── network_module.dart
│           ├── storage_module.dart
│           └── repository_module.dart
│
├── features/                       # Feature-based modules
│   ├── wallet/
│   │   ├── models/                  # Data models (Freezed, JSON serializable)
│   │   │   ├── wallet_model.dart
│   │   │   └── transaction_model.dart
│   │   ├── repository/             # Data access layer
│   │   │   └── wallet_repository.dart
│   │   ├── viewmodels/             # Business logic & state management
│   │   │   ├── wallet_viewmodel.dart
│   │   │   └── transaction_viewmodel.dart
│   │   ├── providers/              # Riverpod providers (expose ViewModels)
│   │   │   └── wallet_providers.dart
│   │   ├── pages/                  # Screen widgets
│   │   │   ├── wallet_screen.dart
│   │   │   └── transaction_detail_screen.dart
│   │   └── widgets/                # Feature-specific widgets
│   │       ├── balance_card.dart
│   │       └── transaction_list_item.dart
│   │
│   ├── send/
│   │   └── [same structure: models, repository, viewmodels, providers, pages, widgets]
│   │
│   ├── receive/
│   │   └── [same structure]
│   │
│   └── settings/
│       └── [same structure]
│
├── shared/                         # Shared across features
│   ├── widgets/
│   │   ├── buttons/
│   │   ├── inputs/
│   │   └── dialogs/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── color_schemes.dart
│   │   ├── typography.dart
│   │   └── theme_providers.dart
│   └── routing/
│       ├── app_router.dart
│       ├── route_config.dart
│       ├── route_guards.dart
│       └── route_names.dart
│
├── platform/                       # Platform-specific code
│   ├── native/
│   │   ├── gdk/
│   │   │   ├── gdk_service.dart
│   │   │   └── gdk_bridge.dart
│   │   └── boltz/
│   │       ├── boltz_service.dart
│   │       └── boltz_bridge.dart
│   └── ffi/
│       └── generated_bindings.dart
│
└── main.dart
```

### 2.2 Key Differences from Current Structure

1. **Feature-Based Organization**: Each feature is self-contained with domain/data/presentation
2. **Clear Layer Separation**: Domain → Data → Presentation
3. **Dependency Injection Module**: Centralized DI configuration
4. **Shared vs Core**: Core = infrastructure, Shared = UI components
5. **Platform Isolation**: All native/FFI code in platform/

---

## 3. Theming Architecture

### 3.1 Theme System Design

**Current State**: Basic theme provider with some customization
**Google Approach**: Comprehensive design system with tokens

```dart
// core/theme/design_tokens.dart
abstract class DesignTokens {
  // Color tokens
  static const Color primary = Color(0xFF1A1A1A);
  static const Color secondary = Color(0xFF4A4A4A);
  static const Color error = Color(0xFFB00020);
  static const Color surface = Color(0xFFFFFFFF);
  
  // Spacing tokens
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  
  // Typography tokens
  static const TextStyle heading1 = TextStyle(...);
  static const TextStyle body1 = TextStyle(...);
}

// shared/theme/app_theme.dart
@freezed
class AppTheme with _$AppTheme {
  const factory AppTheme({
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required SpacingTheme spacing,
    required ShapeTheme shape,
    required AnimationTheme animation,
  }) = _AppTheme;
}

// shared/theme/theme_providers.dart
final appThemeProvider = StateNotifierProvider<ThemeNotifier, AppTheme>(
  (ref) => ThemeNotifier(ref),
);

class ThemeNotifier extends StateNotifier<AppTheme> {
  ThemeNotifier(this.ref) : super(_defaultTheme) {
    _loadTheme();
  }
  
  final Ref ref;
  
  void _loadTheme() {
    final savedTheme = ref.read(preferencesServiceProvider)
        .getString(StorageKeys.theme);
    if (savedTheme != null) {
      state = _themes[savedTheme] ?? _defaultTheme;
    }
  }
  
  Future<void> setTheme(String themeName) async {
    state = _themes[themeName] ?? _defaultTheme;
    await ref.read(preferencesServiceProvider)
        .setString(StorageKeys.theme, themeName);
  }
}

// Usage in MaterialApp
final themeDataProvider = Provider<ThemeData>((ref) {
  final appTheme = ref.watch(appThemeProvider);
  return ThemeData(
    colorScheme: appTheme.colorScheme,
    textTheme: appTheme.textTheme,
    useMaterial3: true,
    // ... other theme properties
  );
});
```

### 3.2 Theme Features

1. **Design Tokens**: Centralized design values
2. **Theme Variants**: Light, Dark, System, Custom (Botev)
3. **Dynamic Theming**: Runtime theme switching
4. **Accessibility**: High contrast, text scaling
5. **Platform Adaptation**: iOS vs Android specific themes

---

## 4. Routing Architecture

### 4.1 Router Configuration

**Current State**: Flat route list in routes.dart
**Google Approach**: Hierarchical, type-safe routing with guards

```dart
// shared/routing/app_router.dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final routerNotifier = ref.watch(routerNotifierProvider);
  
  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: routerNotifier,
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final isOnboardingComplete = authState.isOnboardingComplete;
      final location = state.matchedLocation;
      
      // Guard logic
      if (!isAuthenticated && _requiresAuth(location)) {
        return RoutePaths.login;
      }
      
      if (!isOnboardingComplete && _requiresOnboarding(location)) {
        return RoutePaths.onboarding;
      }
      
      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      
      // Auth routes
      GoRoute(
        path: RoutePaths.auth,
        name: RouteNames.auth,
        builder: (context, state) => const AuthWrapper(),
        routes: [
          GoRoute(
            path: RoutePaths.login,
            name: RouteNames.login,
            builder: (context, state) => const LoginScreen(),
          ),
        ],
      ),
      
      // Main app shell
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: RouteNames.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: RoutePaths.wallet,
            name: RouteNames.wallet,
            builder: (context, state) => const WalletScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
  );
});

// shared/routing/route_guards.dart
class RouteGuards {
  static bool _requiresAuth(String location) {
    return _protectedRoutes.contains(location);
  }
  
  static bool _requiresOnboarding(String location) {
    return _onboardingRequiredRoutes.contains(location);
  }
  
  static const _protectedRoutes = [
    RoutePaths.wallet,
    RoutePaths.send,
    RoutePaths.receive,
  ];
}
```

### 4.2 Navigation Patterns

1. **Type-Safe Navigation**: Use enums/classes instead of strings
2. **Deep Linking**: Full support with parameter validation
3. **Route Guards**: Authentication, onboarding, feature flags
4. **Nested Routing**: Shell routes for tab navigation
5. **Route Analytics**: Automatic navigation tracking

---

## 5. API Layer Architecture

### 5.1 API Client Structure with Chopper

**Current State**: Mix of Chopper, Dio, direct HTTP calls
**Google Approach**: Chopper-based API services with interceptors

```dart
// features/wallet/services/wallet_api_service.dart
import 'package:chopper/chopper.dart';
import 'package:json_annotation/json_annotation.dart';

part 'wallet_api_service.chopper.dart';
part 'wallet_api_service.g.dart';

@ChopperApi(baseUrl: '/api/v1/wallet')
abstract class WalletApiService extends ChopperService {
  @Get(path: '/')
  Future<Response<WalletModel>> getWallet();

  @Get(path: '/transactions')
  Future<Response<List<TransactionModel>>> getTransactions({
    @Query('page') int? page,
    @Query('limit') int? limit,
  });

  @Post(path: '/send')
  Future<Response<TransactionModel>> sendTransaction(
    @Body() SendTransactionRequest request,
  );

  static WalletApiService create({
    required ChopperClient chopperClient,
  }) {
    return _$WalletApiService(chopperClient);
  }
}

// core/network/chopper_client.dart
final chopperClientProvider = Provider<ChopperClient>((ref) {
  return ChopperClient(
    baseUrl: Uri.parse(ApiEndpoints.baseUrl),
    interceptors: [
      AuthInterceptor(ref.read(authTokenManagerProvider)),
      HttpLoggingInterceptor(),
      ErrorInterceptor(ref.read(onUnauthorizedProvider)),
    ],
    converter: const JsonConverter(),
    errorConverter: const JsonConverter(),
  );
});

// Feature-specific API service provider
@riverpod
WalletApiService walletApiService(WalletApiServiceRef ref) {
  final chopperClient = ref.watch(chopperClientProvider);
  return WalletApiService.create(chopperClient: chopperClient);
}
```

### 5.2 API Features

1. **Chopper Services**: Type-safe API services with code generation
2. **Interceptor Chain**: Auth, logging, error handling
3. **Error Handling**: Consistent error mapping
4. **Request/Response Models**: Type-safe models with JSON serialization
5. **Code Generation**: Chopper generates service implementations
6. **Riverpod Annotations**: Providers generated with @riverpod

---

## 6. Data Layer Architecture

### 6.1 Repository Pattern (Simplified)

**Current State**: Direct provider access to services
**Google Approach**: Repository abstraction that handles all data sources internally

```dart
// features/wallet/repository/wallet_repository.dart
abstract class WalletRepository {
  Future<Either<Failure, WalletModel>> getWallet();
  Future<Either<Failure, List<TransactionModel>>> getTransactions();
  Future<Either<Failure, void>> refreshWallet();
}

// features/wallet/repository/wallet_repository_impl.dart
class WalletRepositoryImpl implements WalletRepository {
  final WalletApiService _apiService;  // Chopper API service
  final Isar _isar;                    // For local database
  final GdkService _gdkService;         // For native GDK calls
  final NetworkInfo _networkInfo;
  
  WalletRepositoryImpl({
    required WalletApiService apiService,
    required Isar isar,
    required GdkService gdkService,
    required NetworkInfo networkInfo,
  })  : _apiService = apiService,
        _isar = isar,
        _gdkService = gdkService,
        _networkInfo = networkInfo;
  
  @override
  Future<Either<Failure, WalletModel>> getWallet() async {
    try {
      // Try local cache first
      final cached = await _isar.walletModels.where().findFirst();
      if (cached != null) {
        return Right(cached);
      }
      
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
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(message: e.message));
    } catch (e) {
      return Left(UnknownFailure(message: e.toString()));
    }
  }
  
  // Similar pattern for other methods - repository handles all data sources
}
```

### 6.2 Key Points

1. **Single Repository**: Handles remote, local, and native data sources
2. **Internal Abstraction**: Data source logic encapsulated in repository
3. **Cache Strategy**: Repository decides cache-first vs network-first
4. **Error Handling**: Consistent error mapping to Failure types
5. **Testable**: Easy to mock repository for ViewModel tests

---

## 7. Rust/Native Integration

### 7.1 FFI Architecture

**Current State**: Direct FFI calls, mixed with Dart code
**Google Approach**: Service layer abstraction

```dart
// platform/native/boltz/boltz_service.dart
abstract class BoltzService {
  Future<BoltzSwap> createSwap({
    required String preimageHash,
    required String claimPublicKey,
    required String refundPublicKey,
  });
  
  Future<BoltzSwapStatus> getSwapStatus(String swapId);
}

// platform/native/boltz/boltz_service_impl.dart
class BoltzServiceImpl implements BoltzService {
  final BoltzCore _boltzCore;
  
  BoltzServiceImpl(this._boltzCore);
  
  @override
  Future<BoltzSwap> createSwap({
    required String preimageHash,
    required String claimPublicKey,
    required String refundPublicKey,
  }) async {
    try {
      final result = await _boltzCore.createSwap(
        preimageHash: preimageHash,
        claimPublicKey: claimPublicKey,
        refundPublicKey: refundPublicKey,
      );
      return BoltzSwap.fromNative(result);
    } catch (e) {
      throw BoltzException('Failed to create swap: $e');
    }
  }
}

// platform/native/gdk/gdk_service.dart
abstract class GdkService {
  Future<GdkSession> initializeSession(GdkConfig config);
  Future<GdkBalance> getBalance(int subaccount);
  Future<List<GdkTransaction>> getTransactions(int subaccount);
}

// platform/native/gdk/gdk_service_impl.dart
class GdkServiceImpl implements GdkService {
  final LibGdk _libGdk;
  GdkSession? _session;
  
  GdkServiceImpl(this._libGdk);
  
  @override
  Future<GdkSession> initializeSession(GdkConfig config) async {
    try {
      await _libGdk.initGdk(config);
      _session = await _libGdk.createSession(config);
      return _session!;
    } catch (e) {
      throw GdkException('Failed to initialize GDK: $e');
    }
  }
}
```

### 7.2 Native Integration Features

1. **Service Abstraction**: Abstract interfaces for native code
2. **Error Handling**: Consistent error types
3. **Isolation**: Native code isolated in platform/
4. **Testing**: Mock implementations for testing
5. **Type Safety**: Strong typing for FFI calls

---

## 8. MVVM Implementation (Simplified)

### 8.1 ViewModel Pattern

**Simplified**: ViewModel calls Repository directly (no Use Cases needed)

```dart
// features/wallet/viewmodels/wallet_viewmodel.dart
@freezed
class WalletState with _$WalletState {
  const factory WalletState({
    @Default(false) bool isLoading,
    @Default(false) bool isRefreshing,
    WalletModel? wallet,
    String? errorMessage,
  }) = _WalletState;
}

// features/wallet/providers/wallet_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'wallet_providers.g.dart';

@riverpod
WalletRepository walletRepository(WalletRepositoryRef ref) {
  return WalletRepositoryImpl(
    apiService: ref.watch(walletApiServiceProvider),
    isar: ref.watch(isarProvider),
    gdkService: ref.watch(gdkServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
}

@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  WalletState build() => const WalletState();

  Future<void> loadWallet() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    
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

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true);
    
    final repository = ref.read(walletRepositoryProvider);
    final result = await repository.refreshWallet();
    
    result.fold(
      (failure) => state = state.copyWith(
        isRefreshing: false,
        errorMessage: failure.message,
      ),
      (_) => state = state.copyWith(isRefreshing: false),
    );
    
    await loadWallet();
  }
}
```

### 8.2 View (Widget)

```dart
// features/wallet/pages/wallet_screen.dart
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  @override
  void initState() {
    super.initState();
    // Load wallet when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletViewModelProvider.notifier).loadWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletViewModelProvider);
    final viewModel = ref.read(walletViewModelProvider.notifier);
    
    if (state.isLoading) {
      return const Scaffold(body: LoadingIndicator());
    }
    
    if (state.errorMessage != null) {
      return Scaffold(
        body: ErrorView(
          message: state.errorMessage!,
          onRetry: viewModel.loadWallet,
        ),
      );
    }
    
    if (state.wallet == null) {
      return const Scaffold(body: EmptyState());
    }
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: WalletContent(wallet: state.wallet!),
      ),
    );
  }
}
```

### 8.3 Key Simplifications

1. **No Use Cases**: Business logic in ViewModel or Repository
2. **Direct Repository Access**: ViewModel calls Repository directly
3. **Simple State**: Freezed state classes with clear fields
4. **Riverpod Annotations**: @riverpod generates providers automatically
5. **No Hooks**: Use ConsumerWidget/ConsumerStatefulWidget with initState
6. **Testable**: Easy to mock Repository for ViewModel tests

---

## 9. Testing Architecture (Simplified)

### 9.1 Testing Strategy

```
test/
├── unit/
│   └── features/
│       └── wallet/
│           ├── repository/
│           │   └── wallet_repository_test.dart
│           └── viewmodels/
│               └── wallet_viewmodel_test.dart
│
├── widget/
│   └── features/
│       └── wallet/
│           └── pages/
│               └── wallet_screen_test.dart
│
├── integration/
│   ├── wallet_flow_test.dart
│   ├── send_flow_test.dart
│   └── receive_flow_test.dart
│
└── mocks/
    ├── repositories/
    └── services/
```

### 9.2 Test Examples

```dart
// test/unit/features/wallet/viewmodels/wallet_viewmodel_test.dart
void main() {
  late WalletViewModel viewModel;
  late MockWalletRepository mockRepository;
  
  setUp(() {
    mockRepository = MockWalletRepository();
    viewModel = WalletViewModel(repository: mockRepository);
  });
  
  test('should load wallet successfully', () async {
    // Arrange
    final wallet = WalletModel(id: '1', balance: 1000);
    when(mockRepository.getWallet())
        .thenAnswer((_) async => Right(wallet));
    
    // Act
    await viewModel.loadWallet();
    
    // Assert
    expect(viewModel.state.wallet, wallet);
    expect(viewModel.state.isLoading, false);
    expect(viewModel.state.errorMessage, null);
    verify(mockRepository.getWallet()).called(1);
  });
  
  test('should handle error when repository fails', () async {
    // Arrange
    when(mockRepository.getWallet())
        .thenAnswer((_) async => Left(ServerFailure(message: 'Error')));
    
    // Act
    await viewModel.loadWallet();
    
    // Assert
    expect(viewModel.state.wallet, null);
    expect(viewModel.state.isLoading, false);
    expect(viewModel.state.errorMessage, 'Error');
  });
}

// test/unit/features/wallet/repository/wallet_repository_test.dart
void main() {
  late WalletRepositoryImpl repository;
  late MockApiClient mockApiClient;
  late MockIsar mockIsar;
  late MockGdkService mockGdkService;
  late MockNetworkInfo mockNetworkInfo;
  
  setUp(() {
    mockApiClient = MockApiClient();
    mockIsar = MockIsar();
    mockGdkService = MockGdkService();
    mockNetworkInfo = MockNetworkInfo();
    repository = WalletRepositoryImpl(
      apiClient: mockApiClient,
      isar: mockIsar,
      gdkService: mockGdkService,
      networkInfo: mockNetworkInfo,
    );
  });
  
  test('should return cached wallet if available', () async {
    // Arrange
    final cachedWallet = WalletModel(id: '1', balance: 1000);
    when(mockIsar.walletModels.where().findFirst())
        .thenAnswer((_) async => cachedWallet);
    
    // Act
    final result = await repository.getWallet();
    
    // Assert
    expect(result.isRight(), true);
    result.fold(
      (failure) => fail('Should not fail'),
      (wallet) => expect(wallet, cachedWallet),
    );
  });
}

// test/widget/features/wallet/pages/wallet_screen_test.dart
void main() {
  testWidgets('should display wallet balance', (tester) async {
    // Arrange
    final wallet = WalletModel(id: '1', balance: 1000);
    final mockRepository = MockWalletRepository();
    when(mockRepository.getWallet())
        .thenAnswer((_) async => Right(wallet));
    
    // Act
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walletRepositoryProvider.overrideWithValue(mockRepository),
        ],
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    
    await tester.pumpAndSettle();
    
    // Assert
    expect(find.text('1000'), findsOneWidget);
  });
}
```

### 9.3 Testing Features

1. **Unit Tests**: ViewModels, Repositories
2. **Widget Tests**: UI components, user interactions
3. **Integration Tests**: End-to-end flows
4. **Golden Tests**: UI regression testing (optional)
5. **Performance Tests**: Benchmark critical paths (optional)

---

## 10. Dependency Injection

### 10.1 DI Structure

```dart
// core/di/providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:chopper/chopper.dart';

part 'providers.g.dart';

// Network providers
@riverpod
ChopperClient chopperClient(ChopperClientRef ref) {
  return ChopperClient(
    baseUrl: Uri.parse(ApiEndpoints.baseUrl),
    interceptors: [
      AuthInterceptor(ref.read(authTokenManagerProvider)),
      HttpLoggingInterceptor(),
      ErrorInterceptor(ref.read(onUnauthorizedProvider)),
    ],
    converter: const JsonConverter(),
    errorConverter: const JsonConverter(),
  );
}

@riverpod
NetworkInfo networkInfo(NetworkInfoRef ref) {
  return NetworkInfoImpl(ref.read(connectivityProvider));
}

// Storage providers
@riverpod
Isar isar(IsarRef ref) {
  return Isar.getInstance();
}

@riverpod
SecureStorageService secureStorageService(SecureStorageServiceRef ref) {
  return SecureStorageServiceImpl();
}

// Repository providers (generated with @riverpod)
@riverpod
WalletRepository walletRepository(WalletRepositoryRef ref) {
  return WalletRepositoryImpl(
    apiService: ref.watch(walletApiServiceProvider),
    isar: ref.watch(isarProvider),
    gdkService: ref.watch(gdkServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
}

// ViewModel providers (generated with @riverpod)
@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  WalletState build() => const WalletState();

  Future<void> loadWallet() async {
    // Implementation
  }
}
```

---

## 11. Error Handling

### 11.1 Error Architecture

```dart
// core/errors/failures.dart
abstract class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure({String message = 'Server error'}) : super(message);
}

class NetworkFailure extends Failure {
  const NetworkFailure({String message = 'Network error'}) : super(message);
}

class CacheFailure extends Failure {
  const CacheFailure({String message = 'Cache error'}) : super(message);
}

// core/errors/exceptions.dart
class ServerException implements Exception {
  final String message;
  ServerException(this.message);
}

// Either pattern for error handling
typedef Result<T> = Either<Failure, T>;
```

---

## 12. Performance Optimization

### 12.1 Optimization Strategies

1. **Lazy Loading**: Load data on demand
2. **Caching**: Aggressive caching strategy
3. **Code Splitting**: Feature-based code splitting
4. **Image Optimization**: Cached network images
5. **List Optimization**: ListView.builder with keys
6. **Isolate Usage**: Heavy computations in isolates
7. **Memory Management**: Proper disposal of resources

---

## 13. Security Architecture

### 13.1 Security Measures

1. **Secure Storage**: All sensitive data in FlutterSecureStorage
2. **Certificate Pinning**: API certificate pinning
3. **Biometric Auth**: Local authentication
4. **Encryption**: Data encryption at rest
5. **Key Management**: Secure key storage and rotation
6. **Code Obfuscation**: Release build obfuscation

---

## 14. Monitoring & Analytics

### 14.1 Observability

1. **Error Tracking**: Crashlytics integration
2. **Performance Monitoring**: Performance metrics
3. **Analytics**: User behavior tracking
4. **Logging**: Structured logging with levels
5. **Remote Config**: Feature flags, A/B testing

---

## 15. Build & CI/CD

### 15.1 Build Configuration

1. **Flavors**: dev, staging, production
2. **Code Generation**: Freezed, json_serializable, chopper_generator, riverpod_generator
3. **Linting**: Strict linting rules
4. **Formatting**: Automated code formatting
5. **CI/CD**: Automated testing and deployment

---

## Summary

### Key Improvements (Simplified Architecture)

1. **Simple Structure**: Models → Repository → ViewModel → View (no use cases or entities)
2. **Clear Separation**: Presentation → Data → Platform layers
3. **Riverpod Annotations**: @riverpod for code-generated providers (no hooks_riverpod)
4. **Chopper for API**: Type-safe API services with code generation
5. **Testability**: Every layer independently testable (mock Repository for ViewModel tests)
6. **Scalability**: Feature-based architecture with consistent structure
7. **Maintainability**: Consistent patterns across codebase, less boilerplate
8. **Type Safety**: Strong typing throughout with Freezed models
9. **Error Handling**: Consistent error handling with Either pattern
10. **Performance**: Optimized for large-scale apps
11. **Security**: Enterprise-grade security measures

### Simplified Structure Benefits

- **Less Boilerplate**: No use cases or entities - business logic in ViewModel or Repository
- **Code Generation**: @riverpod and Chopper generate boilerplate automatically
- **Easier to Understand**: Clear flow from View → ViewModel → Repository → Data Sources
- **Still Testable**: Mock Repository interface for ViewModel tests
- **Still Maintainable**: Clear separation of concerns without over-engineering
- **Faster Development**: Less code to write and maintain
- **Type Safety**: Code generation ensures type-safe providers and API services

### Migration Path

1. **Phase 1**: Refactor core infrastructure (network, storage, DI)
2. **Phase 2**: Migrate one feature to new architecture (wallet)
3. **Phase 3**: Migrate remaining features incrementally
4. **Phase 4**: Add comprehensive testing
5. **Phase 5**: Performance optimization and monitoring

This simplified architecture provides a solid foundation for a large-scale, maintainable, and scalable Flutter application following Google's engineering best practices while avoiding over-engineering.


