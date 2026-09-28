import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/app_config.dart';
import '../data/auth_service.dart';
import '../data/push_notification_service.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'reporter_home_shell.dart';
import 'ui_components.dart';

enum _AuthView { login, register, guest }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  UserSession? _session;
  _AuthView _authView = _AuthView.login;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!AppConfig.useApi) {
      // Mock mode: no login required, matches the app's previous behavior.
      setState(() => _loading = false);
      return;
    }

    final restored = await AuthService.restoreSession();
    if (restored != null) {
      setState(() {
        _session = restored;
        _loading = false;
      });
      _registerPushToken(restored);
      return;
    }

    // Dev convenience: fall back to a session built from --dart-define
    // bootstrap values, if provided, instead of forcing a login.
    if (AppConfig.bearerToken.isNotEmpty && AppConfig.responderUserId != 0) {
      final session = UserSession(
        token: AppConfig.bearerToken,
        responderUserId: AppConfig.responderUserId,
        firstName: 'Responder',
        lastName: '',
        email: '',
        role: 'responder',
      );
      setState(() {
        _session = session;
        _loading = false;
      });
      _registerPushToken(session);
      return;
    }

    setState(() => _loading = false);
  }

  void _registerPushToken(UserSession session) {
    PushNotificationService.registerDevice(
      baseUrl: AppConfig.apiBaseUrl,
      bearerToken: session.token,
    );
  }

  Future<void> _handleLogout() async {
    final session = _session;
    setState(() {
      _session = null;
      _authView = _AuthView.login;
    });
    if (session != null) {
      await PushNotificationService.unregisterDevice(
        baseUrl: AppConfig.apiBaseUrl,
        bearerToken: session.token,
      );
    }
    await AuthService.logout(session);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: AuthBackground(
          child: Center(
            child: CircularProgressIndicator(color: RapidAlertColors.emergencyRed),
          ),
        ),
      );
    }

    if (AppConfig.useApi && _session == null) {
      void backToLogin() => setState(() => _authView = _AuthView.login);

      // Register and guest mode replace the login view in place rather than
      // being pushed routes, so the Android back gesture has to be routed
      // back to login explicitly instead of closing the app.
      Widget returnsToLogin(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) backToLogin();
        },
        child: child,
      );

      if (_authView == _AuthView.register) {
        return returnsToLogin(
          RegisterScreen(
            onRegistered: (session) {
              setState(() => _session = session);
              _registerPushToken(session);
            },
            onBackToLogin: backToLogin,
          ),
        );
      }

      if (_authView == _AuthView.guest) {
        return returnsToLogin(
          ReporterHomeShell(session: null, isGuest: true, onLogout: backToLogin),
        );
      }

      return LoginScreen(
        onSignedIn: (session) {
          setState(() => _session = session);
          _registerPushToken(session);
        },
        onRegister: () => setState(() => _authView = _AuthView.register),
        onGuestReport: () => setState(() => _authView = _AuthView.guest),
      );
    }

    if (_session?.isReporter == true) {
      return ReporterHomeShell(session: _session, onLogout: _handleLogout);
    }

    return HomeShell(session: _session, onLogout: _handleLogout);
  }
}
