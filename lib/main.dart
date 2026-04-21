// App entry point. Initializes Flutter binding, builds the ConnectionProvider
// asynchronously so SharedPreferences loads before the first frame, then
// wraps the app in MultiProvider and routes to SplashPage.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/splash_page.dart';
import 'providers/connection_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connectionProvider = await ConnectionProvider.create();
  runApp(LgFlutterTask2App(connectionProvider: connectionProvider));
}

class LgFlutterTask2App extends StatelessWidget {
  final ConnectionProvider connectionProvider;
  const LgFlutterTask2App({super.key, required this.connectionProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionProvider>.value(
          value: connectionProvider,
        ),
      ],
      child: MaterialApp(
        title: 'LG Controller',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const SplashPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
