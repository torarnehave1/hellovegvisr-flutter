import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PushUserInfo {
  final String userId;
  final String phone;
  final String? email;

  const PushUserInfo({required this.userId, required this.phone, this.email});
}

class PushNotificationService {
  static const String _tokenKey = 'fcm_token';
  static const String _baseUrl =
      'https://group-chat-worker.torarnehave.workers.dev';

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'vegvisr_high_importance',
        'Vegvisr Notifications',
        importance: Importance.high,
      );

  FirebaseMessaging? get _messagingOrNull {
    if (kIsWeb) {
      return null;
    }
    _messaging ??= FirebaseMessaging.instance;
    return _messaging;
  }

  /// Initialize push notifications and request permissions
  Future<void> initialize({
    Future<PushUserInfo?> Function()? userInfoProvider,
  }) async {
    final messaging = _messagingOrNull;
    if (messaging == null) {
      return;
    }
    await _initLocalNotifications();
    // Request permission for iOS (Android grants automatically)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get the FCM token
      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(token);
        await _registerWithBackend(token, userInfoProvider);
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) async {
        await _saveToken(newToken);
        await _registerWithBackend(newToken, userInfoProvider);
      });
    }
  }

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _fln.initialize(initSettings);
    await _fln
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }

  Future<void> _registerWithBackend(
    String token,
    Future<PushUserInfo?> Function()? userInfoProvider,
  ) async {
    if (userInfoProvider == null) return;
    final info = await userInfoProvider();
    if (info == null) return;

    final ok = await registerDeviceToken(
      userId: info.userId,
      phone: info.phone,
      email: info.email,
      tokenOverride: token,
    );
    if (!ok) {
      debugPrint('Push registration failed for user ${info.userId}');
    }
  }

  /// Save token locally
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Get the stored FCM token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Register the device token with the backend for a user
  Future<bool> registerDeviceToken({
    required String userId,
    required String phone,
    String? email,
    String? tokenOverride,
  }) async {
    final token = tokenOverride ?? await getToken();
    if (token == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          'fcm_token': token,
          'platform': 'android',
        }),
      );

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Failed to register device token: $e');
      return false;
    }
  }

  /// Unregister device token (on logout)
  Future<bool> unregisterDeviceToken({
    required String userId,
    required String phone,
    String? email,
  }) async {
    final token = await getToken();
    if (token == null) {
      return true; // No token to unregister
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/unregister-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          'fcm_token': token,
        }),
      );

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      print('Failed to unregister device token: $e');
      return false;
    }
  }

  /// Setup foreground message handler
  void setupForegroundHandler({Function(RemoteMessage)? onMessage}) {
    if (kIsWeb) {
      return;
    }
    FirebaseMessaging.onMessage.listen((message) {
      onMessage?.call(message);
      _showLocalNotification(message);
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = notification?.android;
    final title = notification?.title ?? message.data['title'] ?? 'Vegvisr';
    final body = notification?.body ?? message.data['body'] ?? '';

    await _fln.show(
      notification.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: android?.smallIcon ?? '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Setup background/terminated message handler (call in main before runApp)
  static void setupBackgroundHandler(
    Future<void> Function(RemoteMessage) handler,
  ) {
    if (kIsWeb) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(handler);
  }

  /// Get the message that opened the app (if any)
  Future<RemoteMessage?> getInitialMessage() async {
    final messaging = _messagingOrNull;
    if (messaging == null) {
      return null;
    }
    return await messaging.getInitialMessage();
  }

  /// Setup handler for when app is opened from notification
  void setupMessageOpenedAppHandler(
    Function(RemoteMessage) onMessageOpenedApp,
  ) {
    if (kIsWeb) {
      return;
    }
    FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpenedApp);
  }
}
