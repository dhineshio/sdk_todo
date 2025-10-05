import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../model/todo_model.dart';

/// Service class that handles all local notification operations
/// Provides scheduling, cancellation and management of todo reminders
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Initialize the notification service with platform-specific settings
  Future<void> init() async {
    if (_isInitialized) return;

    // Initialize timezone data
    tz.initializeTimeZones();

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // Combined initialization settings
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Initialize the plugin
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _isInitialized = true;
    debugPrint('NotificationService initialized successfully');
  }

  /// Handle notification tap events
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // TODO: Navigate to specific todo when notification is tapped
    // You can add navigation logic here using GetX
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    // Request permission for notifications
    final notificationStatus = await Permission.notification.request();
    
    // For Android 13+ (API 33+), request POST_NOTIFICATIONS permission
    if (notificationStatus.isGranted) {
      // Request iOS-specific permissions
      final bool? result = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      return result ?? true;
    }

    return notificationStatus.isGranted;
  }

  /// Schedule a reminder notification for a todo 10 minutes before its due time
  Future<void> scheduleReminderNotification(Todo todo) async {
    if (!_isInitialized) {
      await init();
    }

    // Calculate reminder time (10 minutes before the todo's due time)
    DateTime? reminderDateTime = _calculateReminderTime(todo);
    
    if (reminderDateTime == null) {
      debugPrint('Cannot schedule notification: Invalid reminder time for todo ${todo.id}');
      return;
    }

    // Check if the reminder time is in the future
    if (reminderDateTime.isBefore(DateTime.now())) {
      debugPrint('Cannot schedule notification: Reminder time is in the past for todo ${todo.id}');
      return;
    }

    // Create notification details
    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'todo_reminders',
      'Todo Reminders',
      channelDescription: 'Notifications for upcoming todo tasks',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(
        todo.description.isNotEmpty ? todo.description : 'Don\'t forget to complete this task!',
        contentTitle: '📋 ${todo.name}',
        summaryText: 'SDK Todo Reminder',
      ),
      actions: [
        const AndroidNotificationAction(
          'mark_done',
          'Mark Done',
          icon: DrawableResourceAndroidBitmap('@drawable/ic_check'),
        ),
        const AndroidNotificationAction(
          'snooze',
          'Snooze 5 min',
          icon: DrawableResourceAndroidBitmap('@drawable/ic_snooze'),
        ),
      ],
    );

    const iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      categoryIdentifier: 'todo_reminder',
      threadIdentifier: 'todo_reminders',
    );

    final platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    // Schedule the notification
    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        todo.id.hashCode, // Use todo ID hash as notification ID
        '📋 Reminder: ${todo.name}',
        todo.description.isNotEmpty 
            ? todo.description 
            : 'Your task is due in 10 minutes!',
        tz.TZDateTime.from(reminderDateTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: todo.id,
      );

      debugPrint('Notification scheduled for todo ${todo.id} at $reminderDateTime');
    } catch (e) {
      debugPrint('Error scheduling notification for todo ${todo.id}: $e');
    }
  }

  /// Calculate the reminder time (10 minutes before the todo's due time)
  DateTime? _calculateReminderTime(Todo todo) {
    try {
      // If reminderTime is already set, use it
      if (todo.reminderTime != null) {
        return todo.reminderTime!.subtract(const Duration(minutes: 10));
      }

      // If time is specified, combine date and time
      if (todo.time != null && todo.time!.isNotEmpty) {
        final timeParts = todo.time!.split(':');
        if (timeParts.length == 2) {
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          
          final dueDateTime = DateTime(
            todo.date.year,
            todo.date.month,
            todo.date.day,
            hour,
            minute,
          );
          
          return dueDateTime.subtract(const Duration(minutes: 10));
        }
      }

      // Fallback: Use date with default time (9:00 AM)
      final dueDateTime = DateTime(
        todo.date.year,
        todo.date.month,
        todo.date.day,
        9, // Default hour: 9 AM
        0, // Default minute: 0
      );
      
      return dueDateTime.subtract(const Duration(minutes: 10));
    } catch (e) {
      debugPrint('Error calculating reminder time for todo ${todo.id}: $e');
      return null;
    }
  }

  /// Cancel a scheduled notification for a specific todo
  Future<void> cancelNotification(String todoId) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(todoId.hashCode);
      debugPrint('Notification cancelled for todo $todoId');
    } catch (e) {
      debugPrint('Error cancelling notification for todo $todoId: $e');
    }
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }

  /// Get all pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Error getting pending notifications: $e');
      return [];
    }
  }

  /// Reschedule all notifications for todos with reminders
  Future<void> rescheduleAllNotifications(List<Todo> todos) async {
    // Cancel all existing notifications first
    await cancelAllNotifications();

    // Schedule notifications for all todos that have reminder times
    for (final todo in todos) {
      if (!todo.isCompleted && _shouldScheduleNotification(todo)) {
        await scheduleReminderNotification(todo);
      }
    }

    debugPrint('Rescheduled notifications for ${todos.length} todos');
  }

  /// Check if a notification should be scheduled for this todo
  bool _shouldScheduleNotification(Todo todo) {
    // Don't schedule for completed todos
    if (todo.isCompleted) return false;

    // Check if the todo has a future date or time
    final reminderTime = _calculateReminderTime(todo);
    if (reminderTime == null) return false;

    // Only schedule if reminder time is in the future
    return reminderTime.isAfter(DateTime.now());
  }

  /// Show an immediate notification (for testing purposes)
  Future<void> showImmediateNotification(String title, String body) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'immediate_channel',
      'Immediate Notifications',
      channelDescription: 'For immediate notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iOSPlatformChannelSpecifics = DarwinNotificationDetails();

    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
    );
  }
}