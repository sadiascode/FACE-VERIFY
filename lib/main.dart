import 'package:flutter/material.dart';
import 'face_detection_screen.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Face Verify",
      debugShowCheckedModeBanner: false,
      home: FaceDetectionScreen(),
    );
  }
}