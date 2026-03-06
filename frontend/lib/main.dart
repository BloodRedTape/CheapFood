import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'cubit/auth_cubit.dart';
import 'screens/login_screen.dart';
import 'screens/restaurants_screen.dart';

void main() {
  runApp(const CheapFoodApp());
}

class CheapFoodApp extends StatelessWidget {
  const CheapFoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(),
      child: ShadApp(
        title: 'CheapFood',
        home: const _RootNavigator(),
      ),
    );
  }
}

class _RootNavigator extends StatefulWidget {
  const _RootNavigator();

  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        final nav = _navigatorKey.currentState!;
        if (state is AuthSuccess) {
          nav.pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const RestaurantsScreen(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
            (_) => false,
          );
        } else if (state is AuthInitial) {
          nav.pushAndRemoveUntil(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LoginScreen(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
            (_) => false,
          );
        }
      },
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (_) => PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
        ),
      ),
    );
  }
}
