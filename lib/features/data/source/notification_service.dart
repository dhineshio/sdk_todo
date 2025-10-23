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
    if (_isInitialized) {
      debugPrint('🔔 NotificationService already initialized');
      return;
    }

    debugPrint('🚀 Initializing NotificationService...');
    
    try {
      // Initialize timezone data
      tz.initializeTimeZones();
      debugPrint('✅ Timezone data initialized');
    } catch (e) {
      debugPrint('❌ Error initializing timezone data: $e');
      throw e;
    }

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
    try {
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      debugPrint('✅ Flutter Local Notifications plugin initialized');
    } catch (e) {
      debugPrint('❌ Error initializing Flutter Local Notifications: $e');
      throw e;
    }

    _isInitialized = true;
    debugPrint('🎉 NotificationService initialized successfully');
  }

  /// Handle notification tap events
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // TODO: Navigate to specific todo when notification is tapped
    // You can add navigation logic here using GetX
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    debugPrint('🔐 Requesting notification permissions...');
    
    try {
      // Check current notification permission status
      final currentStatus = await Permission.notification.status;
      debugPrint('📱 Current notification permission status: $currentStatus');
      
      // Request permission for notifications
      final notificationStatus = await Permission.notification.request();
      debugPrint('📱 Notification permission result: $notificationStatus');
      
      // For Android 13+ (API 33+), also check POST_NOTIFICATIONS permission
      if (notificationStatus.isGranted) {
        // Request iOS-specific permissions
        final bool? iosResult = await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );

        debugPrint('🍎 iOS notification permissions result: $iosResult');
        
        // Check for exact alarm permission on Android (needed for precise scheduling)
        try {
          final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
          debugPrint('⏰ Exact alarm permission status: $exactAlarmStatus');
          
          if (!exactAlarmStatus.isGranted) {
            final exactAlarmResult = await Permission.scheduleExactAlarm.request();
            debugPrint('⏰ Exact alarm permission request result: $exactAlarmResult');
          }
        } catch (e) {
          debugPrint('⚠️  Note: Could not check exact alarm permission (may not be needed): $e');
        }
        
        final finalResult = iosResult ?? true;
        debugPrint(finalResult ? '✅ All notification permissions granted' : '❌ Some notification permissions denied');
        return finalResult;
      }

      debugPrint('❌ Notification permission denied');
      return false;
    } catch (e) {
      debugPrint('❌ Error requesting notification permissions: $e');
      return false;
    }
  }

  /// Schedule a reminder notification for a todo 10 minutes before its due time
  Future<void> scheduleReminderNotification(Todo todo) async {
    if (!_isInitialized) {
      debugPrint('NotificationService not initialized, initializing now...');
      await init();
    }

    // Don't schedule notifications for completed todos
    if (todo.isCompleted) {
      debugPrint('Not scheduling notification for completed todo: ${todo.name}');
      return;
    }

    // Calculate reminder time (10 minutes before the todo's due time)
    DateTime? reminderDateTime = _calculateReminderTime(todo);
    
    if (reminderDateTime == null) {
      debugPrint('❌ Cannot schedule notification: Invalid reminder time for todo "${todo.name}" (${todo.id})');
      return;
    }

    // Check if the reminder time is in the future
    final now = DateTime.now();
    if (reminderDateTime.isBefore(now)) {
      debugPrint('❌ Cannot schedule notification: Reminder time is in the past for todo "${todo.name}"');
      debugPrint('   Reminder time: $reminderDateTime');
      debugPrint('   Current time: $now');
      return;
    }

    debugPrint('✅ Scheduling notification for "${todo.name}"');
    debugPrint('   Due date: ${todo.date}');
    debugPrint('   Due time: ${todo.time ?? 'No specific time'}');
    debugPrint('   Reminder time: $reminderDateTime');
    debugPrint('   Time until reminder: ${reminderDateTime.difference(now).inMinutes} minutes');

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
      final notificationId = todo.id.hashCode;
      final tzDateTime = tz.TZDateTime.from(reminderDateTime, tz.local);
      
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId, // Use todo ID hash as notification ID
        '📋 Reminder: ${todo.name}',
        todo.description.isNotEmpty 
            ? todo.description 
            : 'Your task is due in 10 minutes!',
        tzDateTime,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: todo.id,
      );

      debugPrint('🔔 Notification successfully scheduled!');
      debugPrint('   Notification ID: $notificationId');
      debugPrint('   Scheduled for: $tzDateTime');
      
      // Verify the notification was scheduled by checking pending notifications
      final pendingNotifications = await getPendingNotifications();
      final isScheduled = pendingNotifications.any((notif) => notif.id == notificationId);
      
      if (isScheduled) {
        debugPrint('✅ Verification: Notification found in pending list');
      } else {
        debugPrint('⚠️  Warning: Notification not found in pending list');
      }
      
    } catch (e) {
      debugPrint('❌ Error scheduling notification for todo "${todo.name}": $e');
      debugPrint('   Stack trace: ${StackTrace.current}');
    }
  }

  /// Calculate the reminder time (10 minutes before the todo's due time)
  DateTime? _calculateReminderTime(Todo todo) {
    try {
      DateTime dueDateTime;
      
      // Priority 1: If reminderTime is already set, use it directly (no additional 10 min subtraction)
      if (todo.reminderTime != null) {
        return todo.reminderTime!;
      }

      // Priority 2: If time is specified, combine date and time
      if (todo.time != null && todo.time!.isNotEmpty) {
        final timeParts = todo.time!.split(':');
        if (timeParts.length == 2) {
          try {
            final hour = int.parse(timeParts[0]);
            final minute = int.parse(timeParts[1]);
            
            // Validate hour and minute ranges
            if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
              dueDateTime = DateTime(
                todo.date.year,
                todo.date.month,
                todo.date.day,
                hour,
                minute,
              );
              
              // Calculate reminder time (10 minutes before due time)
              final reminderTime = dueDateTime.subtract(const Duration(minutes: 10));
              
              debugPrint('Scheduled notification for ${todo.name} - Due: $dueDateTime, Reminder: $reminderTime');
              return reminderTime;
            }
          } catch (e) {
            debugPrint('Error parsing time "${todo.time}" for todo ${todo.id}: $e');
          }
        }
      }

      // Priority 3: Check if todo.date has time information (not just date)
      if (todo.date.hour != 0 || todo.date.minute != 0) {
        // The todo.date already contains time information
        dueDateTime = todo.date;
        final reminderTime = dueDateTime.subtract(const Duration(minutes: 10));
        
        debugPrint('Using todo.date with time for ${todo.name} - Due: $dueDateTime, Reminder: $reminderTime');
        return reminderTime;
      }

      // Priority 4: For date-only todos, use end of day (11:59 PM) as due time
      // This ensures notifications are shown during the day for daily tasks
      dueDateTime = DateTime(
        todo.date.year,
        todo.date.month,
        todo.date.day,
        23, // 11 PM
        50, // 50 minutes (so reminder is at 11:40 PM, giving 10 min before end of day)
      );
      
      final reminderTime = dueDateTime.subtract(const Duration(minutes: 10));
      
      debugPrint('Using default end-of-day time for ${todo.name} - Due: $dueDateTime, Reminder: $reminderTime');
      return reminderTime;
      
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
    if (!_isInitialized) {
      await init();
    }
    
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
    
    debugPrint('🔔 Immediate test notification sent: $title');
  }
  
  /// Schedule a test notification 30 seconds from now (for debugging purposes)
  Future<void> scheduleTestNotification() async {
    if (!_isInitialized) {
      await init();
    }
    
    final testTime = DateTime.now().add(const Duration(seconds: 30));
    
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'For testing notification scheduling',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iOSPlatformChannelSpecifics = DarwinNotificationDetails();

    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        999999, // Test notification ID
        '🧪 Test Notification',
        'This test notification was scheduled 30 seconds ago to verify timing works correctly.',
        tz.TZDateTime.from(testTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      
      debugPrint('🔔 Test notification scheduled for 30 seconds from now: $testTime');
    } catch (e) {
      debugPrint('❌ Error scheduling test notification: $e');
    }
  }
  
  /// Debug method to print all pending notifications
  Future<void> debugPendingNotifications() async {
    try {
      final pending = await getPendingNotifications();
      debugPrint('📋 Pending Notifications (${pending.length} total):');
      
      if (pending.isEmpty) {
        debugPrint('   No pending notifications found.');
        return;
      }
      
      for (int i = 0; i < pending.length; i++) {
        final notif = pending[i];
        debugPrint('   ${i + 1}. ID: ${notif.id}');
        debugPrint('      Title: ${notif.title ?? 'No title'}');
        debugPrint('      Body: ${notif.body ?? 'No body'}');
        debugPrint('      Payload: ${notif.payload ?? 'No payload'}');
      }
    } catch (e) {
      debugPrint('❌ Error getting pending notifications: $e');
    }
  }
  
  /// Comprehensive debug method to check notification system status
  Future<void> debugNotificationSystem() async {
    debugPrint('🔍 === NOTIFICATION SYSTEM DEBUG ===');
    
    // Check initialization status
    debugPrint('📱 Initialization Status: ${_isInitialized ? "✅ Initialized" : "❌ Not Initialized"}');
    
    // Check permissions
    try {
      final notificationStatus = await Permission.notification.status;
      debugPrint('🔐 Notification Permission: $notificationStatus');
      
      try {
        final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
        debugPrint('⏰ Exact Alarm Permission: $exactAlarmStatus');
      } catch (e) {
        debugPrint('⏰ Exact Alarm Permission: Not available or not needed');
      }
    } catch (e) {
      debugPrint('❌ Error checking permissions: $e');
    }
    
    // Check pending notifications
    await debugPendingNotifications();
    
    // Test immediate notification capability
    debugPrint('🧪 Testing immediate notification...');
    try {
      await showImmediateNotification(
        'System Test', 
        'Notification system is working! Time: ${DateTime.now()}'
      );
      debugPrint('✅ Immediate notification sent successfully');
    } catch (e) {
      debugPrint('❌ Failed to send immediate notification: $e');
    }
    
    debugPrint('🔍 === END DEBUG ===');
  }
}