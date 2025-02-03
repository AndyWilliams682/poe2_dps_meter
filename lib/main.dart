import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';

import 'package:window_manager/window_manager.dart';

import 'package:dps_meter/src/rust/api/screenshot.dart';
import 'package:dps_meter/src/rust/frb_generated.dart';

double logBase(num x, num base) => log(x) / log(base);

String dpsDisplay(double dps) {
  if(dps <= 0) {
    return "0";
  }
  var magnitude = logBase(dps, 1000).floor();
  var letter = "";
  switch (magnitude) {
    case < 1:
      letter = "";
    case 1:
      letter = "k"; // thousands
    case 2:
      letter = "m"; // millions
    case 3:
      letter = "b"; // billions
    case 4:
      letter = "t"; // trillions
    case > 4:
      letter = "e$magnitude"; // Use scientific beyond trillions
  }
  return (dps / pow(1000, magnitude)).toStringAsFixed(2) + letter;
}

Future<void> main() async {
  await RustLib.init();

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  windowManager.setAlwaysOnTop(true);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Test App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: MainPage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  var isCapturing = false;
  var capturingLabel = "Idle";
  var label = ""; // TODO: Remove
  var counter = 0; // TODO: Remove
  Timer? timer;

  var damageReading = 0;
  var accumulatedDamage = 0;
  var damageHistory = <int>[];

  var dt = 250; // ms
  final timeWindow = 4000; // ms
  final windowIndexSize = 4000 ~/ 250;
  var elapsedTime = 0;

  var windowDps = 0.0;
  var overallDps = 0.0;

  void toggleCapturing() async {
    isCapturing = !isCapturing;
    
    if (isCapturing) {
      capturingLabel = "Measuring";
      _startTimer();
    } else {
      capturingLabel = "Idle";
      _stopTimer();
    }
    notifyListeners();
  }

  void _captureDamage() async {
    damageReading = (await readDamage(x: 576, y: 0, width: 1344, height: 65));
    if (damageReading == 0) {
      if (damageHistory.isEmpty) {
        return;
      } else if (accumulatedDamage < damageHistory[damageHistory.length - 1]) {
        accumulatedDamage = damageHistory[damageHistory.length - 1];
      }
    }
    damageHistory.add(accumulatedDamage + damageReading); // TODO: Improve OCR accuracy through testing
    if ((damageHistory.length <= 1) || (damageReading == 0)) {
      return;
    }
    _calculateOverallDps();
    _calculateWindowDps();
    notifyListeners();
  }

  void _calculateOverallDps() {
    overallDps = 1000 * damageHistory[damageHistory.length - 1] / elapsedTime; // Converting to damage per second
  }

  void _calculateWindowDps() {
    windowDps = 1000 * (damageHistory[damageHistory.length - 1] -
                        damageHistory[max(0, damageHistory.length - windowIndexSize - 1)]) / timeWindow;
  }

  void _startTimer() {
    timer = Timer.periodic(Duration(milliseconds: dt), (timer) {
      if (isCapturing) { // Check the flag inside the timer callback
        elapsedTime += dt;
        counter += 1; // TODO: Remove counter
        _captureDamage();
        print(damageHistory);
        print(accumulatedDamage);
        print(damageReading);
      } else {
        _stopTimer(); // Stop if the flag is set to false
      }
    });
  }

  void _stopTimer() {
    damageHistory = [];
    accumulatedDamage = 0;
    timer?.cancel();
    timer = null;
  }

  @override
  void dispose() {
    _stopTimer(); // Important: Cancel the timer when the widget is disposed
    super.dispose();
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {   
    var appState = context.watch<MyAppState>();
    var capturingLabel = appState.capturingLabel;
    var overallDps = appState.overallDps;
    var windowDps = appState.windowDps;

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            children: [
              Text("Overall DPS: ${dpsDisplay(overallDps)}"),
              Text("Window DPS: ${dpsDisplay(windowDps)}"),
              ElevatedButton(onPressed: appState.toggleCapturing, child: Text(capturingLabel)) // TODO: replace with other syntax
            ],
          ),
        ),
      ),
    );
  }
}
