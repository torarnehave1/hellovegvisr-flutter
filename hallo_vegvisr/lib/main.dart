import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/create_graph_screen.dart';
import 'screens/my_graphs_screen.dart';
import 'screens/edit_graph_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/group_chat_list_screen.dart';
import 'screens/group_chat_screen.dart';
import 'screens/group_info_screen.dart';
import 'screens/join_group_screen.dart';
import 'screens/debug_fcm_token_screen.dart';
import 'services/push_notification_service.dart';

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Handle background message (notification is shown automatically by FCM)
}

bool firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (will fail gracefully if not configured)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;
    // Setup background message handler only if Firebase is initialized
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase not configured - push notifications will be disabled
    debugPrint('Firebase not configured: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late GoRouter _router;
  final PushNotificationService? _pushService =
      kIsWeb ? null : PushNotificationService();
  final _authService = AuthService();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _initRouter();
    _initPushNotifications();
  }

  Future<void> _initPushNotifications() async {
    if (!firebaseInitialized || _pushService == null) {
      return; // Skip if Firebase is not configured
    }

    await _pushService!.initialize(userInfoProvider: _getUserInfoForPush);

    // Handle foreground messages (debug visibility)
    _pushService!.setupForegroundHandler(onMessage: (message) {
      debugPrint('FCM foreground message: ${message.data} | ${message.notification}');
      final notification = message.notification;
      final title = notification?.title ?? 'New message';
      final body = notification?.body ?? message.data.toString();
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('$title: ${body.length > 80 ? body.substring(0, 80) + '…' : body}')),
      );
    });

    // Handle notification tap when app was in background
    _pushService!.setupMessageOpenedAppHandler((message) {
      debugPrint('FCM onMessageOpenedApp: ${message.data}');
      final data = message.data;
      final groupId = data['group_id'];
      final groupName = data['group_name'];
      if (groupId != null) {
        _router.push('/group-chat/$groupId', extra: groupName);
      }
    });

    // Check if app was opened from a notification
    final initialMessage = await _pushService!.getInitialMessage();
    if (initialMessage != null) {
      final data = initialMessage.data;
      final groupId = data['group_id'];
      final groupName = data['group_name'];
      if (groupId != null) {
        // Delay navigation to allow router to initialize
        Future.delayed(const Duration(milliseconds: 500), () {
          _router.push('/group-chat/$groupId', extra: groupName);
        });
      }
    }
  }

  Future<PushUserInfo?> _getUserInfoForPush() async {
    final loggedIn = await _authService.isLoggedIn();
    if (!loggedIn) return null;

    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();

    if (userId == null || phone == null) {
      return null;
    }

    return PushUserInfo(userId: userId, phone: phone, email: email);
  }

  void _initRouter() {
    _router = GoRouter(
      redirect: (context, state) async {
        final prefs = await SharedPreferences.getInstance();
        final loggedIn = prefs.getBool('logged_in') ?? false;

        // Redirect to login if not logged in
        if (!loggedIn && state.matchedLocation != '/login') {
          return '/login';
        }

        // Redirect to home if logged in and on login page
        if (loggedIn && state.matchedLocation == '/login') {
          return '/';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => HomeScreen(
            openDrawer: state.uri.queryParameters['openDrawer'] == 'true',
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/create-graph',
          builder: (context, state) => const CreateGraphScreen(),
        ),
        GoRoute(
          path: '/my-graphs',
          builder: (context, state) => const MyGraphsScreen(),
        ),
        GoRoute(
          path: '/edit-graph/:graphId',
          builder: (context, state) {
            final graphId = state.pathParameters['graphId']!;
            return EditGraphScreen(graphId: graphId);
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/group-chats',
          builder: (context, state) => const GroupChatListScreen(),
        ),
        GoRoute(
          path: '/group-chat/:groupId',
          builder: (context, state) {
            final groupId = state.pathParameters['groupId']!;
            final groupName = state.extra as String?;
            return GroupChatScreen(groupId: groupId, groupName: groupName);
          },
        ),
        GoRoute(
          path: '/group-info/:groupId',
          builder: (context, state) {
            final groupId = state.pathParameters['groupId']!;
            final groupName = state.extra as String?;
            return GroupInfoScreen(groupId: groupId, groupName: groupName);
          },
        ),
        GoRoute(
          path: '/join/:inviteCode',
          builder: (context, state) {
            final inviteCode = state.pathParameters['inviteCode']!;
            return JoinGroupScreen(inviteCode: inviteCode);
          },
        ),
        GoRoute(
          path: '/debug/fcm-token',
          builder: (context, state) => const DebugFcmTokenScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: 'Hallo Vegvisr',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 20, 195, 17)),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
