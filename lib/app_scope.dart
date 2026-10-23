import 'package:flutter/widgets.dart';

import 'api/hub_api.dart';
import 'auth/auth_controller.dart';

/// Makes the session available to every screen and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AuthController> {
  const AppScope({super.key, required AuthController auth, required super.child}) : super(notifier: auth);

  static AuthController authOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// For callbacks and initState: reads the session without subscribing to changes.
  static AuthController readAuth(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static HubApi apiOf(BuildContext context) => readAuth(context).api;
}
