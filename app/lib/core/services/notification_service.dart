import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local-only notifications. Nothing goes through Google/Apple push servers.
class NotificationService with WidgetsBindingObserver {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _foreground = true;
  String? activeConvId; // conversation currently on screen
  void Function(String payload)? onTap;
  bool hidePreview = false;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) onTap?.call(r.payload!);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _foreground = state == AppLifecycleState.resumed;
  bool get inForeground => _foreground;

  int _id(String s) => s.hashCode & 0x7fffffff;

  Future<void> message({required String convId, required String title, required String body, bool muted = false}) async {
    if (muted) return;
    if (_foreground && activeConvId == convId) return;
    await _plugin.show(
      _id(convId),
      hidePreview ? 'PrivChat' : title,
      hidePreview ? 'New message' : body,
      const NotificationDetails(
        android: AndroidNotificationDetails('messages', 'Messages',
            channelDescription: 'New messages', importance: Importance.high, priority: Priority.high,
            category: AndroidNotificationCategory.message, visibility: NotificationVisibility.private),
        iOS: DarwinNotificationDetails(),
      ),
      payload: convId,
    );
  }

  Future<void> incomingCall(String callId, String name) => _plugin.show(
        _id(callId),
        'Incoming call',
        name,
        const NotificationDetails(
          android: AndroidNotificationDetails('calls', 'Calls',
              channelDescription: 'Incoming calls', importance: Importance.max, priority: Priority.max,
              category: AndroidNotificationCategory.call, fullScreenIntent: true, ongoing: true, autoCancel: false),
          iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
        ),
        payload: 'call',
      );

  Future<void> cancelCall(String callId) => _plugin.cancel(_id(callId));
  Future<void> cancelConv(String convId) => _plugin.cancel(_id(convId));
}
