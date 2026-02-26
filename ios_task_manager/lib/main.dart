import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/models/profile.dart';
import 'src/screens/admin/admin_shell.dart';
import 'src/screens/employee/employee_home_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/services/supabase_service.dart';
import 'src/ui/app_theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_0bZ99guMKLcUhzxiev7I9w_KE7PLh02',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  }

  runApp(const TaskManagerApp());
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty
          ? const MissingSetupScreen()
          : const AuthGate(),
    );
  }
}

class MissingSetupScreen extends StatelessWidget {
  const MissingSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Required')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Missing Supabase configuration. Run with:\n\n'
          'flutter run --dart-define=SUPABASE_URL=your-url',
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SupabaseService(Supabase.instance.client);

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, _) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return LoginScreen(service: service);
        }

        return FutureBuilder<Profile?>(
          future: service.fetchCurrentProfile(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(snapshot.error.toString()),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: service.signOut,
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final profile = snapshot.data;
            if (profile == null) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No profile found for this user.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: service.signOut,
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (profile.role.isAdmin) {
              return AdminShell(service: service, currentUser: profile);
            }

            return EmployeeHomeScreen(service: service, currentUser: profile);
          },
        );
      },
    );
  }
}
