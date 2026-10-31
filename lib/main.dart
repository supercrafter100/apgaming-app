import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_scope.dart';
import 'auth/auth_controller.dart';
import 'demo/demo_frame.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('nl_BE');
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final auth = AuthController();
  runApp(GamingHubApp(auth: auth));
  await auth.restore();
}

class GamingHubApp extends StatelessWidget {
  const GamingHubApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: auth,
      child: MaterialApp(
        title: 'AP Gaming Hub',
        scaffoldMessengerKey: auth.push.messengerKey,
        debugShowCheckedModeBanner: false,
        theme: buildHubTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('nl', 'BE'),
        supportedLocales: const [Locale('nl', 'BE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => DemoFrame(child: child!),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.authOf(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (auth.status) {
        AuthStatus.loading => const Scaffold(
          key: ValueKey('loading'),
          body: Center(child: CircularProgressIndicator.adaptive()),
        ),
        AuthStatus.signedOut => const LoginScreen(key: ValueKey('login')),
        // Keyed by user so switching accounts starts with fresh screens.
        AuthStatus.signedIn => HomeShell(key: ValueKey('home-${auth.profile!.id}')),
      },
    );
  }
}
