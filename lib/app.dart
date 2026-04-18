import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/messaging_provider.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_panel_screen.dart';
import 'screens/commuter/commuter_booking_screen.dart';
import 'screens/driver/driver_dashboard_screen.dart';
import 'screens/driver/driver_login_screen.dart';
import 'screens/driver/driver_register_screen.dart';
import 'screens/driver/pending_verification_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/placeholder_screen.dart';

/// Routing rules:
///   - `/` and `/commuter` and `/feedback` are public.
///   - `/driver/login`, `/driver/register`, `/driver/pending` are public
///     (they ARE the auth surface).
///   - Anything else under `/driver/` requires a signed-in user; we
///     bounce to /driver/login otherwise.
///   - `/admin/*` requires a signed-in user too; the admin screen
///     itself does the admins/{email} doc check before rendering.
GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshNotifier(ref),
    redirect: (context, state) {
      final authValue = ref.read(authStateProvider);
      final user = authValue.valueOrNull;
      final loc = state.matchedLocation;

      const publicDriverRoutes = {
        '/driver/login',
        '/driver/register',
        '/driver/pending',
      };

      final needsDriverAuth =
          loc.startsWith('/driver/') && !publicDriverRoutes.contains(loc);
      final needsAdminAuth = loc.startsWith('/admin');

      if ((needsDriverAuth || needsAdminAuth) && user == null) {
        return '/driver/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LandingScreen()),
      GoRoute(
        path: '/commuter',
        builder: (_, _) => const CommuterBookingScreen(),
      ),
      GoRoute(
        path: '/feedback',
        builder: (_, _) => const FeedbackScreen(),
      ),
      GoRoute(
        path: '/driver/login',
        builder: (_, _) => const DriverLoginScreen(),
      ),
      GoRoute(
        path: '/driver/register',
        builder: (_, _) => const DriverRegisterScreen(),
      ),
      GoRoute(
        path: '/driver/pending',
        builder: (_, _) => const PendingVerificationScreen(),
      ),
      GoRoute(
        path: '/driver/dashboard',
        builder: (_, _) => const DriverDashboardScreen(),
      ),
      GoRoute(
        path: '/driver/profile',
        builder: (_, _) => const PlaceholderScreen(title: 'Profile'),
      ),
      GoRoute(
        path: '/driver/history',
        builder: (_, _) => const PlaceholderScreen(title: 'Ride history'),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const AdminPanelScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (_, _) => const AdminDashboardScreen(),
      ),
    ],
  );
}

/// Bridges Riverpod's auth stream into GoRouter's `refreshListenable`,
/// so route guards re-evaluate the moment a user signs in or out.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));

class TrikeKoToApp extends ConsumerWidget {
  const TrikeKoToApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mount the push-registration notifier at the app root so its
    // auth-state listener wires up before any screen renders.
    ref.watch(pushRegistrationProvider);

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TrikeKoTo',
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
