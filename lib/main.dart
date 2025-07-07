// main.dart (updated background task registration and WorkManager logic)

import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'background_service.dart'; // add this
import 'package:flutter/foundation.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';


// Notification channel setup
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'device_status_channel',
  'Device Status Alerts',
  description: 'Notifications for device connectivity issues',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();


class BluetoothDeviceListScreen extends StatefulWidget {
  const BluetoothDeviceListScreen({Key? key}) : super(key: key);

  @override
  _BluetoothDeviceListScreenState createState() => _BluetoothDeviceListScreenState();
}

class _BluetoothDeviceListScreenState extends State<BluetoothDeviceListScreen> {
  List<BluetoothDiscoveryResult> devices = [];
  bool isDiscovering = false;

  bool _notificationActive = false;
  DateTime? _lastUpdateTime;
  BluetoothDevice? _selectedDevice;
  bool showWifiSetup = false;
  bool showSettings = false;

  late StreamSubscription<BluetoothDiscoveryResult> _discoveryStreamSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    startDiscovery();
  }

  void startDiscovery() {
    setState(() {
      devices.clear();
      isDiscovering = true;
    });

    _discoveryStreamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      setState(() {
        final existingIndex = devices.indexWhere((d) => d.device.address == result.device.address);
        if (existingIndex >= 0) {
          devices[existingIndex] = result;
        } else {
          devices.add(result);
        }
      });
    });

    _discoveryStreamSubscription.onDone(() {
      setState(() {
        isDiscovering = false;
      });
    });
  }

  Future<void> _requestPermissions() async {
  if (Platform.isAndroid) {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }
}

  @override
  void dispose() {
    _discoveryStreamSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Row(
    children: [
      const Text('Air Analyzer'),
      const SizedBox(width: 8),
      Builder(
        builder: (context) {
          if (_notificationActive) {
            return Tooltip(
              message: 'Device offline since ${timeago.format(_lastUpdateTime!)}',
              child: const Icon(Icons.wifi_off, color: Colors.red),
            );
          } else if (_lastUpdateTime != null) {
            return Tooltip(
              message: 'Last update: ${timeago.format(_lastUpdateTime!)}',
              child: const Icon(Icons.wifi, color: Colors.green),
            );
          }
          return const Icon(Icons.wifi, color: Colors.grey);
        },
      ),
    ],
  ),
  actions: [
    IconButton(
      icon: const Icon(Icons.bluetooth_searching),
      tooltip: "Scan Bluetooth Devices",
      onPressed: () async {
        final BluetoothDevice? device = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BluetoothDeviceListScreen()),
        );
        if (device != null) {
          setState(() {
            _selectedDevice = device;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Selected device: ${device.name ?? device.address}')),
          );
        }
      },
    ),
    IconButton(
      icon: Icon(showWifiSetup ? Icons.wifi_off : Icons.wifi),
      tooltip: showWifiSetup ? "Hide Wi-Fi Setup" : "Show Wi-Fi Setup",
      onPressed: () {
        setState(() {
          showWifiSetup = !showWifiSetup;
        });
      },
    ),
    IconButton(
      icon: Icon(showSettings ? Icons.visibility_off : Icons.settings),
      tooltip: showSettings ? "Hide Settings" : "Show Settings",
      onPressed: () {
        setState(() {
          showSettings = !showSettings;
        });
      },
    ),
    IconButton(
      icon: const Icon(Icons.logout),
      tooltip: "Logout",
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
      },
    ),
  ],
),

      body: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (context, index) {
          final device = devices[index].device;
          return ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(device.name ?? 'Unknown device'),
            subtitle: Text(device.address),
            trailing: devices[index].rssi != null ? Text('RSSI: ${devices[index].rssi}') : null,
            onTap: () {
              Navigator.of(context).pop(device);
            },
          );
        },
      ),
    );
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await requestIgnoreBatteryOptimizations();
  // Initialize local notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Initialize background service
  await Workmanager().initialize(
    callbackDispatcher, // from background_service.dart
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    "task_projectx_monitor",
    "simplePeriodicTask",
    frequency: Duration(minutes: 15),
    initialDelay: Duration(minutes: 1),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  runApp(ProjectXApp(flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin));
}


Future<void> requestIgnoreBatteryOptimizations() async {
  if (Platform.isAndroid) {
    var isIgnoring = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!isIgnoring) {
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.garik.airanalyzer', // replace with your package ID
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    }
  }
}

Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin notifications,
  String message,
) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
  'background_channel',
  'Device Status',
  channelDescription: 'Device status notifications',
  importance: Importance.max,
  priority: Priority.high,
  icon: '@mipmap/ic_launcher',  // specify your notification icon here
  enableVibration: true,
  ongoing: false,
  autoCancel: true,
);


  await notifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
    'Device Status',
    message,
    const NotificationDetails(android: androidDetails),
  );
}

class ProjectXApp extends StatelessWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  
  const ProjectXApp({Key? key, required this.flutterLocalNotificationsPlugin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Air Analyzer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.tealAccent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          foregroundColor: Colors.tealAccent,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1F1F1F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.tealAccent),
            borderRadius: BorderRadius.circular(8),
          ),
          labelStyle: const TextStyle(color: Colors.tealAccent),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1F1F1F),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: AuthGate(flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin),
    );
  }
}

class AuthGate extends StatelessWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  
  const AuthGate({Key? key, required this.flutterLocalNotificationsPlugin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return ProjectXHome(flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin);
        }
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passController.text.trim());
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to Air Analyzer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autofillHints: const [AutofillHints.password],
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _signIn,
              child: _loading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectXHome extends StatefulWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  
  const ProjectXHome({Key? key, required this.flutterLocalNotificationsPlugin}) : super(key: key);

  @override
  _ProjectXHomeState createState() => _ProjectXHomeState();
}

class _ProjectXHomeState extends State<ProjectXHome> with WidgetsBindingObserver {
  // Timers
  Timer? _autoRefreshTimer;
  Timer? _connectionCheckTimer;
  BluetoothConnection? _bluetoothConnection;
  BluetoothDevice? _espDevice;
  BluetoothDevice? _selectedDevice;
  
  // Database and connectivity
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Device ID
  final String deviceId = "dAxXdU5e4PVqpvre1iXZWIWRl5k1";
  
  // Sensor data
  double? temperature;
  int? humidity;
  int? co2;
  DateTime? _lastUpdateTime;
  
  // Settings values
  double? tempUp, tempDown;
  int? humUp, humDown;
  int? coUp, coDown;
  
  // Modes
  bool rejimTemp = true;
  bool rejimHum = true;
  bool rejimCo = true;
  
  // UI state
  bool loading = true;
  bool saving = false;
  String status = "Loading...";
  bool _notificationActive = false;
  bool showSettings = false;
  bool showWifiSetup = false;
  
  // Controllers
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _setupConnectivityListener();
    Future.delayed(const Duration(seconds: 2), () {
      loadAllData();
      _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!loading) loadAllData();
      });
      _connectionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_lastUpdateTime != null) _checkConnection(suppressNotification: true);
      });
    });
  }

  Future<void> _connectToEspBluetooth() async {
  if (_selectedDevice == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please select your AirAnalyzer device first.")),
    );
    return;
  }

  try {
    _bluetoothConnection = await BluetoothConnection.toAddress(_selectedDevice!.address);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Connected to ${_selectedDevice!.name ?? _selectedDevice!.address}")),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bluetooth connection failed: $e")),
    );
  }
}

Future<void> _sendWifiCredentialsViaBluetooth(String ssid, String password) async {
  if (_bluetoothConnection == null || !_bluetoothConnection!.isConnected) {
    await _connectToEspBluetooth();
    if (_bluetoothConnection == null || !_bluetoothConnection!.isConnected) {
      return;
    }
  }

  String data = '$ssid,$password\n'; // ESP32 expects SSID,password newline separated
  try {
    _bluetoothConnection!.output.add(Uint8List.fromList(data.codeUnits));
    await _bluetoothConnection!.output.allSent;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Wi-Fi credentials sent via Bluetooth")),
    );
    ssidController.clear();
    passController.clear();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to send data: $e")),
    );
  }
}

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.notification,
        Permission.ignoreBatteryOptimizations,
      ].request();
      await Permission.bluetoothScan.request();
await Permission.bluetoothConnect.request();
await Permission.locationWhenInUse.request();  // Needed on some devices for BT scanning

    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      if (result == ConnectivityResult.none) {
        _showConnectionNotification("No internet connection");
      } else if (_notificationActive) {
        _clearAllNotifications();
      }
    });
  }

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  switch (state) {
    case AppLifecycleState.resumed:
      _checkConnection(suppressNotification: true);
      break;
    case AppLifecycleState.paused:
      break;
    case AppLifecycleState.inactive:
    case AppLifecycleState.detached:
    case AppLifecycleState.hidden: // ✅ Add this line
      break;
  }
}


  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _connectionCheckTimer?.cancel();
    dbRef.child('devices/$deviceId/settings').onValue.drain();
    dbRef.child('devices/$deviceId/modes').onValue.drain();
    _clearAllNotifications();
    ssidController.dispose();
    passController.dispose();
    _bluetoothConnection?.dispose();
    _bluetoothConnection = null;
    super.dispose();
  }

  Future<void> _clearAllNotifications() async {
    if (!mounted) return;
    await widget.flutterLocalNotificationsPlugin.cancelAll();
    if (mounted) {
      setState(() => _notificationActive = false);
    }
  }

bool get _isAppActive {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
}

 Future<void> _checkConnection({bool suppressNotification = false}) async {
  if (_lastUpdateTime == null) return;

  try {
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      if (!_notificationActive && !suppressNotification && _isAppActive) {
        await _showConnectionNotification("No internet connection");
      }
      return;
    }

    final snapshot = await dbRef.child('devices/$deviceId/sensors')
      .get()
      .timeout(const Duration(seconds: 5));

    if (!snapshot.exists) {
      if (!_notificationActive && !suppressNotification && _isAppActive) {
        await _showConnectionNotification("Device not responding");
      }
      return;
    }

    final lastUpdate = snapshot.child('timestamp').value as int?;
    if (lastUpdate == null) return;

    final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate * 1000);
    final minutesSinceUpdate = DateTime.now().difference(lastUpdateTime).inMinutes;

    if (minutesSinceUpdate > 5) {
      if (!_notificationActive && !suppressNotification && _isAppActive) {
        await _showConnectionNotification("Device data outdated (${minutesSinceUpdate}m)");
      }
    } else if (_notificationActive) {
      await _clearAllNotifications();
    }

    setState(() => _lastUpdateTime = lastUpdateTime);
  } catch (e) {
    print('Connection check error: $e');
    if (!_notificationActive && !suppressNotification && _lastUpdateTime != null && _isAppActive) {
      await _showConnectionNotification("Connection error");
    }
  }
}

  Future<bool> _checkFirebaseConnection() async {
    try {
      final response = await dbRef.child('devices/$deviceId/sensors')
        .get()
        .timeout(const Duration(seconds: 5));

      if (!response.exists) return false;

      final lastUpdate = response.child('timestamp').value as int?;
      if (lastUpdate == null) return false;

      final minutesSinceUpdate = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastUpdate * 1000))
        .inMinutes;

      return minutesSinceUpdate <= 2;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showConnectionNotification(String message) async {
    final vibrationPattern = Int64List(4)
      ..[0] = 0
      ..[1] = 1000
      ..[2] = 500
      ..[3] = 1000;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'device_status_channel',
      'Device Status',
      channelDescription: 'Critical device status alerts',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      ongoing: false,
      autoCancel: true,
      actions: [
        AndroidNotificationAction(
          'dismiss',
          'Dismiss',
          cancelNotification: true,
        ),
      ],
    );

    await widget.flutterLocalNotificationsPlugin.show(
      0,
      '⚠️ Device Status',
      message,
      const NotificationDetails(android: androidDetails),
    );

    if (mounted) {
      setState(() => _notificationActive = true);
    }
  }
  
 Future<void> loadAllData() async {
  setState(() => loading = true);

  try {
    // Load settings
    final settingsSnap = await dbRef.child('devices/$deviceId/settings').once();
    if (settingsSnap.snapshot.exists) {
      final settings = settingsSnap.snapshot.value as Map<dynamic, dynamic>;
      setState(() {
        tempUp = (settings['temp_up'] as num?)?.toDouble();
        tempDown = (settings['temp_down'] as num?)?.toDouble();
        humUp = settings['hum_up'] as int?;
        humDown = settings['hum_down'] as int?;
        coUp = settings['co_up'] as int?;
        coDown = settings['co_down'] as int?;
      });
    }

    // Load modes
    final modesSnap = await dbRef.child('devices/$deviceId/modes').once();
    if (modesSnap.snapshot.exists) {
      final modes = modesSnap.snapshot.value as Map<dynamic, dynamic>;
      setState(() {
        rejimTemp = modes['rejim_temp'] ?? true;
        rejimHum = modes['rejim_hum'] ?? true;
        rejimCo = modes['rejim_co'] ?? true;
      });
    }

    // Load sensor data
    final sensorsSnap = await dbRef.child('devices/$deviceId/sensors').once();
    if (sensorsSnap.snapshot.exists) {
      final sensors = sensorsSnap.snapshot.value as Map<dynamic, dynamic>;
      final newUpdateTime = DateTime.fromMillisecondsSinceEpoch(
          (sensors['timestamp'] as int) * 1000);

      setState(() {
        temperature = (sensors['temperature'] as num?)?.toDouble();
        humidity = sensors['humidity'] as int?;
        co2 = sensors['co2'] as int?;
        _lastUpdateTime = newUpdateTime;
        status = "Data loaded at ${timeago.format(newUpdateTime)}";
      });

      if (_notificationActive) {
        await _clearAllNotifications();
      }
    }

    // 🔥 New logic to trigger notification if data is stale
    if (_lastUpdateTime != null) {
      final minutesSinceUpdate = DateTime.now().difference(_lastUpdateTime!).inMinutes;

      if (minutesSinceUpdate > 5 && !_notificationActive) {
        await _showConnectionNotification("Device data outdated (${minutesSinceUpdate}m)");
      } else if (minutesSinceUpdate <= 5 && _notificationActive) {
        await _clearAllNotifications();
      }
    }

  } catch (e) {
    setState(() => status = "Error loading data: ${e.toString()}");
    print('Error loading data: $e');
  } finally {
    if (mounted) {
      setState(() => loading = false);
    }
  }
}

Future<void> _connectToDevice(BluetoothDevice device) async {
  try {
    final connection = await BluetoothConnection.toAddress(device.address);
    print('Connected to ${device.name}');
    setState(() {
      _bluetoothConnection = connection;
      status = 'Connected to ${device.name}';
    });
  } catch (e) {
    print("Connection failed: $e");
    setState(() => status = 'Failed to connect');
  }
}


  void _setupFirebaseListeners() {
    // Settings listener
    dbRef.child('devices/$deviceId/settings').onValue.listen((event) {
      if (event.snapshot.exists) {
        final settings = event.snapshot.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            tempUp = (settings['temp_up'] as num?)?.toDouble();
            tempDown = (settings['temp_down'] as num?)?.toDouble();
            humUp = settings['hum_up'] as int?;
            humDown = settings['hum_down'] as int?;
            coUp = settings['co_up'] as int?;
            coDown = settings['co_down'] as int?;
          });
        }
      }
    });

    // Modes listener
    dbRef.child('devices/$deviceId/modes').onValue.listen((event) {
      if (event.snapshot.exists) {
        final modes = event.snapshot.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            rejimTemp = modes['rejim_temp'] ?? true;
            rejimHum = modes['rejim_hum'] ?? true;
            rejimCo = modes['rejim_co'] ?? true;
          });
        }
      }
    });
  }

  Future<void> saveSettings() async {
    setState(() {
      saving = true;
      status = "Saving settings...";
    });

    try {
      await dbRef.child('devices/$deviceId/settings').set({
        'temp_up': tempUp,
        'temp_down': tempDown,
        'hum_up': humUp,
        'hum_down': humDown,
        'co_up': coUp,
        'co_down': coDown,
      });

      await dbRef.child('devices/$deviceId/modes').set({
        'rejim_temp': rejimTemp,
        'rejim_hum': rejimHum,
        'rejim_co': rejimCo,
      });

      setState(() {
        status = "Settings saved.";
      });
    } catch (e) {
      setState(() {
        status = "Error saving settings: $e";
      });
    } finally {
      setState(() {
        saving = false;
      });
    }
  }

  List<BluetoothDiscoveryResult> _scanResults = [];
bool _scanning = false;

Future<void> _startBluetoothScan() async {
  setState(() {
    _scanResults.clear();
    _scanning = true;
  });

  try {
    _bluetoothConnection?.dispose();
    _bluetoothConnection = null;

    BluetoothConnection.toAddress(null); // cleanup any previous

    FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      setState(() {
        final alreadyExists = _scanResults.any((e) => e.device.address == r.device.address);
        if (!alreadyExists) _scanResults.add(r);
      });
    }).onDone(() {
      setState(() => _scanning = false);
    });
  } catch (e) {
    print("Bluetooth scan error: $e");
    setState(() => _scanning = false);
  }
}


  Widget buildWifiSetup() {
    return Card(
      color: const Color(0xFF1F1F1F),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Wi-Fi Setup", style: TextStyle(color: Colors.tealAccent, fontSize: 18)),
            const SizedBox(height: 10),
            TextField(
              controller: ssidController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "SSID"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Password"),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.wifi),
              label: const Text("Send Wi-Fi Credentials"),
              onPressed: () async {
  if (ssidController.text.isEmpty || passController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please fill both SSID and Password")),
    );
    return;
  }
  await _sendWifiCredentialsViaBluetooth(ssidController.text.trim(), passController.text.trim());
},

            ),
          ],
        ),
      ),
    );
  }

  Widget buildNumberField(String label, String suffix, dynamic value, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value?.toString(),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget buildBoolDropdown(String label, bool value, Function(bool?) onChanged, {String trueLabel = "True", String falseLabel = "False"}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<bool>(
        value: value,
        dropdownColor: const Color(0xFF1F1F1F),
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: true, child: Text(trueLabel)),
          DropdownMenuItem(value: false, child: Text(falseLabel)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget buildLiveData() {
    const TextStyle labelStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.tealAccent);
    const TextStyle valueStyle = TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white);
    return Card(
      color: const Color(0xFF1F1F1F),
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        child: Column(
          children: [
            const Text("Live Data", style: labelStyle),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Temperature:", style: labelStyle),
                Text(
                  temperature != null ? "${temperature!.toStringAsFixed(1)} °C" : "--",
                  style: valueStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Humidity:", style: labelStyle),
                Text(humidity != null ? "$humidity %" : "--", style: valueStyle),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CO₂:", style: labelStyle),
                Text(co2 != null ? "$co2 ppm" : "--", style: valueStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSettings() {
    return Card(
      color: const Color(0xFF1F1F1F),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("Settings", style: TextStyle(color: Colors.tealAccent, fontSize: 18)),
            buildNumberField('Temp Upper Limit', "°C", tempUp, (v) {
              setState(() {
                tempUp = double.tryParse(v);
              });
            }),
            buildNumberField('Temp Lower Limit', "°C", tempDown, (v) {
              setState(() {
                tempDown = double.tryParse(v);
              });
            }),
            buildNumberField('Humidity Upper Limit', "%", humUp, (v) {
              setState(() {
                humUp = int.tryParse(v);
              });
            }),
            buildNumberField('Humidity Lower Limit', "%", humDown, (v) {
              setState(() {
                humDown = int.tryParse(v);
              });
            }),
            buildNumberField('CO₂ Upper Limit', "ppm", coUp, (v) {
              setState(() {
                coUp = int.tryParse(v);
              });
            }),
            buildNumberField('CO₂ Lower Limit', "ppm", coDown, (v) {
              setState(() {
                coDown = int.tryParse(v);
              });
            }),
            buildBoolDropdown('Temperature Mode', rejimTemp, (v) {
              if (v != null) setState(() => rejimTemp = v);
            }, trueLabel: "Heat", falseLabel: "Cool"),
            buildBoolDropdown('Humidity Mode', rejimHum, (v) {
              if (v != null) setState(() => rejimHum = v);
            }, trueLabel: "Humidify", falseLabel: "Dehumidify"),
            buildBoolDropdown('CO₂ Mode', rejimCo, (v) {
              if (v != null) setState(() => rejimCo = v);
            }, trueLabel: "Ventilate", falseLabel: "Recirculate"),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: saving ? null : saveSettings,
              child: saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                    )
                  : const Text("Save Settings"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Air Analyzer'),
            const SizedBox(width: 8),
            Builder(
              builder: (context) {
                if (_notificationActive) {
                  return Tooltip(
                    message: 'Device offline since ${timeago.format(_lastUpdateTime!)}',
                    child: const Icon(Icons.wifi_off, color: Colors.red),
                  );
                } else if (_lastUpdateTime != null) {
                  return Tooltip(
                    message: 'Last update: ${timeago.format(_lastUpdateTime!)}',
                    child: const Icon(Icons.wifi, color: Colors.green),
                  );
                }
                return const Icon(Icons.wifi, color: Colors.grey);
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(showWifiSetup ? Icons.wifi_off : Icons.wifi),
            tooltip: showWifiSetup ? "Hide Wi-Fi Setup" : "Show Wi-Fi Setup",
            onPressed: () {
              setState(() {
                showWifiSetup = !showWifiSetup;
              });
            },
          ),
          IconButton(
            icon: Icon(showSettings ? Icons.visibility_off : Icons.settings),
            tooltip: showSettings ? "Hide Settings" : "Show Settings",
            onPressed: () {
              setState(() {
                showSettings = !showSettings;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
          IconButton(
  icon: Icon(Icons.bluetooth_searching),
  tooltip: "Scan Bluetooth",
  onPressed: () {
    _startBluetoothScan();
  },
),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  buildLiveData(),
                  if (_scanning) ...[
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  const Text(
                    "Scanning for devices...",
                    style: TextStyle(color: Colors.white),
                  ),
                ] else if (_scanResults.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "Select a Bluetooth device:",
                    style: TextStyle(color: Colors.tealAccent),
                  ),
                  const SizedBox(height: 10),
                  // build a List of devices
                  for (var result in _scanResults)
                    ListTile(
                      leading: const Icon(Icons.bluetooth, color: Colors.tealAccent),
                      title: Text(
                        result.device.name ?? "Unknown",
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        result.device.address,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onTap: () => _connectToDevice(result.device),
                    ),
                ],
                  if (showSettings) buildSettings(),
                  if (showWifiSetup) buildWifiSetup(),
                  const SizedBox(height: 16),
                  Text(status, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}