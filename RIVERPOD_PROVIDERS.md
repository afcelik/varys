# Riverpod Providers - Backend Connection Layer

This document explains how the Riverpod providers work in the Varys Flutter application for backend communication.

## Overview

The backend connection layer uses **Riverpod** for state management and dependency injection. All providers are defined in `lib/core/network/api_client.dart`.

## Provider Hierarchy

```
AuthNotifier (StateNotifierProvider)
    │
    ├── apiClientProvider (FutureProvider<ApiClient>)
    │       │
    │       └── SecureStorage (flutter_secure_storage)
    │
    ├── dioProvider (Provider<Dio>)
    │       └── apiClientProvider
    │
    ├── isAuthenticatedProvider (FutureProvider<bool>)
    │       └── SecureStorage.hasApiToken()
    │
    ├── serverUrlProvider (FutureProvider<String>)
    │       └── SecureStorage.getServerUrl()
    │
    └── apiTokenProvider (FutureProvider<String?>)
            └── SecureStorage.getApiToken()
```

## Detailed Provider Explanations

### 1. `authNotifierProvider` - StateNotifierProvider
**Type:** `StateNotifierProvider<AuthNotifier, AsyncValue<void>>`

The central controller for authentication state changes. It manages:
- **Server URL updates** - Persists new URL to secure storage
- **API Token updates** - Persists new token to secure storage  
- **Logout** - Clears the API token

```dart
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier();
});
```

**Usage in UI:**
```dart
final notifier = ref.read(authNotifierProvider.notifier);
await notifier.updateServerUrl('http://new-server:8000');
await notifier.setApiToken('new-token');
await notifier.logout();
```

The `AsyncValue<void>` state allows the UI to show loading indicators during async operations.

---

### 2. `apiClientProvider` - FutureProvider<ApiClient>
**Type:** `FutureProvider<ApiClient>`

Creates an `ApiClient` instance by reading stored credentials from secure storage. Since reading from secure storage is asynchronous, this uses a `FutureProvider`.

```dart
final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  return await ApiClient.fromStorage();
});
```

**How it works:**
1. Calls `SecureStorage.getServerUrl()` - returns stored URL or default (`http://10.0.2.2:8000`)
2. Calls `SecureStorage.getApiToken()` - returns stored token or `null`
3. Creates `ApiClient` with these credentials
4. The `ApiClient` constructor automatically adds the `Authorization: Bearer <token>` header if token exists

**Usage in features:**
```dart
// In a consumer widget
final apiClientAsync = ref.watch(apiClientProvider);

apiClientAsync.when(
  data: (apiClient) => apiClient.get('/notes'),
  loading: () => CircularProgressIndicator(),
  error: (e, st) => Text('Error: $e'),
);

// Or use .requireValue when you know it's loaded
final apiClient = ref.watch(apiClientProvider).requireValue;
await apiClient.post('/notes', data: {'title': 'New Note'});
```

**Important:** When settings change, call `ref.invalidate(apiClientProvider)` to force recreation with new credentials.

---

### 3. `dioProvider` - Provider<Dio>
**Type:** `Provider<Dio>`

Provides direct access to the underlying Dio instance for advanced use cases (custom interceptors, multipart requests, etc.).

```dart
final dioProvider = Provider<Dio>((ref) {
  final apiClient = ref.watch(apiClientProvider).requireValue;
  return apiClient.dio;
});
```

**Usage:**
```dart
final dio = ref.watch(dioProvider);
// Add custom interceptor for a specific feature
dio.interceptors.add(CustomInterceptor());
```

**Note:** This throws if `apiClientProvider` hasn't resolved yet. Use with `.requireValue` or handle the async state.

---

### 4. `isAuthenticatedProvider` - FutureProvider<bool>
**Type:** `FutureProvider<bool>`

Simple check if user has an API token stored. Used by the router redirect logic.

```dart
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  return await SecureStorage.hasApiToken();
});
```

**Used in router redirect:**
```dart
redirect: (context, state) async {
  final hasToken = await SecureStorage.hasApiToken();
  // ... redirect logic
}
```

---

### 5. `serverUrlProvider` - FutureProvider<String>
**Type:** `FutureProvider<String>`

Returns the currently configured server URL.

```dart
final serverUrlProvider = FutureProvider<String>((ref) async {
  return await SecureStorage.getServerUrl();
});
```

**Usage:**
```dart
final serverUrl = ref.watch(serverUrlProvider);
serverUrl.when(
  data: (url) => Text('Connected to: $url'),
  loading: () => Text('Loading...'),
  error: (e, st) => Text('Error'),
);
```

---

### 6. `apiTokenProvider` - FutureProvider<String?>
**Type:** `FutureProvider<String?>`

Returns the current API token (nullable). Mostly for debugging/display purposes.

```dart
final apiTokenProvider = FutureProvider<String?>((ref) async {
  return await SecureStorage.getApiToken();
});
```

---

## SecureStorage Integration

All persistent data uses `flutter_secure_storage` via the `SecureStorage` wrapper class:

| Key | Purpose | Default |
|-----|---------|---------|
| `server_url` | Backend API base URL | `http://10.0.2.2:8000` (Android emulator) |
| `api_token` | Bearer token for authentication | `null` |

**Platform-specific secure storage:**
- **iOS:** Keychain
- **Android:** Keystore (API 23+) / EncryptedSharedPreferences
- **Linux:** libsecret
- **macOS:** Keychain
- **Windows:** Credential Manager

---

## Router Integration

The `AppRouter.createRouter(ref)` function uses `SecureStorage.hasApiToken()` directly in the redirect callback:

```dart
static GoRouter createRouter(WidgetRef ref) {
  return GoRouter(
    initialLocation: homePath,
    redirect: (context, state) async {
      final hasToken = await SecureStorage.hasApiToken();
      final isSettingsRoute = state.matchedLocation == settingsPath;
      
      if (!hasToken && !isSettingsRoute) {
        return settingsPath; // Redirect to settings
      }
      return null;
    },
    routes: [...],
  );
}
```

**Why direct SecureStorage call instead of provider?**
The redirect callback runs during navigation, before the provider system is fully available. Reading directly from secure storage is synchronous-enough for this purpose.

---

## Settings Screen Flow

```
SettingsScreen
    │
    ├── _loadSavedSettings() → SecureStorage.getServerUrl() + getApiToken()
    │       └── Populates TextFormFields
    │
    ├── _testConnection() → Creates temporary ApiClient with form values
    │       └── Calls GET /health
    │       └── Shows success/error result
    │
    └── _saveSettings() → authNotifierProvider.notifier
            ├── updateServerUrl()
            ├── setApiToken()
            └── ref.invalidate(apiClientProvider)  // Critical! Recreates ApiClient
```

---

## Usage Examples

### Making an API Call in a Feature

```dart
class NotesRepository {
  final Ref ref;
  
  NotesRepository(this.ref);
  
  Future<List<Note>> getNotes() async {
    final apiClient = await ref.read(apiClientProvider.future);
    final response = await apiClient.get<List<dynamic>>('/notes');
    return response.data!.map((json) => Note.fromJson(json)).toList();
  }
  
  Future<Note> createNote(String title) async {
    final apiClient = await ref.read(apiClientProvider.future);
    final response = await apiClient.post('/notes', data: {'title': title});
    return Note.fromJson(response.data!);
  }
}
```

### Using with Riverpod Generator (riverpod_generator)

```dart
@riverpod
Future<List<Note>> notes(NotesRef ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  final response = await apiClient.get<List<dynamic>>('/notes');
  return response.data!.map((json) => Note.fromJson(json)).toList();
}

// In UI
final notesAsync = ref.watch(notesProvider);
```

### Handling Authentication State Changes

```dart
class AuthGate extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    
    return authState.when(
      data: (_) => const MainApp(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}
```

---

## Key Design Decisions

1. **FutureProvider for ApiClient** - Reading from secure storage is async; FutureProvider handles this naturally
2. **AuthNotifier for mutations** - StateNotifier provides clean API for async mutations with loading/error states
3. **Invalidation pattern** - After settings change, `ref.invalidate(apiClientProvider)` forces recreation
4. **Default server URL** - Uses Android emulator default (`10.0.2.2`) for development
5. **No AI keys on client** - As per requirements, only backend auth token is stored; AI provider keys stay on server
6. **Turkish UI** - All user-facing strings are in Turkish per project requirements

---

## Testing the Connection

The `/health` endpoint is used for connection testing:

```dart
Future<bool> testConnection() async {
  try {
    final response = await _dio.get('/health');
    return response.statusCode == 200;
  } on DioException {
    return false;
  }
}
```

Expected backend response:
```json
GET /health
→ 200 OK
{
  "status": "healthy",
  "version": "1.0.0"
}
```