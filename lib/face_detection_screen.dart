import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  CameraController? _cameraController;

  late final FaceDetector _faceDetector;

  bool _isInitialized = false;
  bool _isDetecting = false;

  // FACE
  int _faceCount = 0;
  String _faceStatus = 'No face detected';

  // LANDMARKS
  bool _leftEyeLandmark = false;
  bool _rightEyeLandmark = false;
  bool _noseLandmark = false;

  // EYES
  String _leftEyeStatus = '-';
  String _rightEyeStatus = '-';

  double? _leftEyeProbability;
  double? _rightEyeProbability;

  // SMILE
  String _smileStatus = '-';
  double? _smileProbability;

  // HEAD
  double? _headX;
  double? _headY;
  double? _headZ;


  // LIVENESS
  bool _blinkCompleted = false;
  bool _leftCompleted = false;
  bool _rightCompleted = false;
  bool _straightCompleted = false;
  bool _livePersonVerified = false;

  String _livenessMessage = 'Look at the camera and blink';

  // Used to prevent the same closed-eye frame if it is close (don't say its blink)
  bool _eyesWereClosed = false;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _initializeCamera();
  }


  // CAMERA INITIALIZATION
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _faceStatus = 'No camera found';
        });
        return;
      }

      final frontCamera = cameras.firstWhere(

        //camera select front
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, //Android camera frame format
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      setState(() {
        _isInitialized = true;
      });

      await controller.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint('Camera initialization error: $e');

      if (!mounted) return;

      setState(() {
        _faceStatus = 'Camera error';
      });
    }
  }


  // CAMERA IMAGE PROCESSING
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting) return;

    _isDetecting = true;

    try {
      final inputImage = _convertCameraImage(image);

      if (inputImage == null) {
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted) return;

      if (faces.isEmpty) {
        _handleNoFace();
        return;
      }

      if (faces.length > 1) {
        _handleMultipleFaces(faces.length);
        return;
      }

      _handleFace(faces.first);
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  // CAMERA IMAGE -> ML KIT INPUT IMAGE
  InputImage? _convertCameraImage(CameraImage image) {
    final controller = _cameraController;

    if (controller == null) {
      return null;
    }

    final camera = controller.description;

    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );

    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) {
      return null;
    }

    if (image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // NO FACE
  void _handleNoFace() {
    setState(() {
      _faceCount = 0;

      _faceStatus = 'No face detected';

      _leftEyeStatus = '-';
      _rightEyeStatus = '-';

      _leftEyeProbability = null;
      _rightEyeProbability = null;

      _smileStatus = '-';
      _smileProbability = null;

      _headX = null;
      _headY = null;
      _headZ = null;

      _leftEyeLandmark = false;
      _rightEyeLandmark = false;
      _noseLandmark = false;

      _eyesWereClosed = false;

      if (!_livePersonVerified) {
        _livenessMessage = 'Place your face inside the frame';
      }
    });
  }


  // MULTIPLE FACES
  void _handleMultipleFaces(int count) {
    setState(() {
      _faceCount = count;

      _faceStatus = '$count faces detected';

      _livenessMessage = 'Only one person should be visible';
    });
  }


  // SINGLE FACE
  void _handleFace(Face face) {
    final leftEye = face.leftEyeOpenProbability;

    final rightEye = face.rightEyeOpenProbability;

    final smile = face.smilingProbability;

    final leftEyeLandmark = face.landmarks[FaceLandmarkType.leftEye];

    final rightEyeLandmark = face.landmarks[FaceLandmarkType.rightEye];

    final noseLandmark = face.landmarks[FaceLandmarkType.noseBase];

    setState(() {

      // FACE DETECTION
      _faceCount = 1;
      _faceStatus = 'Face detected ✓';

      // LANDMARKS
      _leftEyeLandmark = leftEyeLandmark != null;

      _rightEyeLandmark = rightEyeLandmark != null;

      _noseLandmark = noseLandmark != null;

      // EYE DETECTION
      _leftEyeProbability = leftEye;
      _rightEyeProbability = rightEye;

      _leftEyeStatus = _getEyeStatus(leftEye);
      _rightEyeStatus = _getEyeStatus(rightEye);

      // SMILE DETECTION
      _smileProbability = smile;
      _smileStatus = _getSmileStatus(smile);

      // HEAD ANGLE
      _headX = face.headEulerAngleX;
      _headY = face.headEulerAngleY;
      _headZ = face.headEulerAngleZ;
    });


    // LIVENESS
    _checkLiveness(face);
  }


  // EYE STATUS
  String _getEyeStatus(double? probability) {
    if (probability == null) {
      return 'Unknown';
    }

    if (probability >= 0.70) {
      return 'Open';
    }

    if (probability <= 0.30) {
      return 'Closed';
    }

    return 'Uncertain';
  }


  // SMILE STATUS
  String _getSmileStatus(double? probability) {
    if (probability == null) {
      return 'Unknown';
    }

    if (probability >= 0.70) {
      return 'Smiling';
    }

    return 'Not Smiling';
  }


  // LIVENESS CHECK
  // 1. BLINK
  // 2. TURN LEFT
  // 3. TURN RIGHT
  // 4. STRAIGHT
  void _checkLiveness(Face face) {
    if (_straightCompleted) {
      return;
    }

    final leftEye = face.leftEyeOpenProbability;

    final rightEye = face.rightEyeOpenProbability;

    final headY = face.headEulerAngleY;

    // STEP 1: BLINK
    if (!_blinkCompleted) {
      if (leftEye != null && rightEye != null) {
        final bothEyesClosed = leftEye < 0.25 && rightEye < 0.25;

        final bothEyesOpen = leftEye > 0.75 && rightEye > 0.75;

        // Eyes became closed
        if (bothEyesClosed) {
          _eyesWereClosed = true;
        }

        // Eyes closed -> open = blink
        if (_eyesWereClosed && bothEyesOpen) {
          setState(() {
            _blinkCompleted = true;

            _livenessMessage =
                'Blink detected ✓\n'
                'Now turn your head LEFT';
          });

          _eyesWereClosed = false;
        }
      }

      return;
    }

    // STEP 2: TURN LEFT
    if (!_leftCompleted) {
      if (headY != null && headY < -15) {
        setState(() {
          _leftCompleted = true;

          _livenessMessage =
              'Left movement detected ✓\n'
              'Now turn your head RIGHT';
        });
      }

      return;
    }


    // STEP 3: TURN RIGHT
    if (!_rightCompleted) {
      if (headY != null && headY > 15) {
        setState(() {
          _rightCompleted = true;

          _livePersonVerified = true;

          _livenessMessage = 'Live Person Verified ✓\nNow look STRAIGHT';
        });

        debugPrint('================================');
        debugPrint('LIVE PERSON VERIFIED');
        debugPrint('================================');
      }

      return;
    }

    // STEP 4: STRAIGHT
    if (!_straightCompleted) {
      if (headY != null && headY.abs() < 5) {
        setState(() {
          _straightCompleted = true;

          _livenessMessage = 'All liveness steps completed ✓';
        });

        debugPrint('================================');
        debugPrint('STRAIGHT POSITION DETECTED');
        debugPrint('================================');

        _capturePicture();
      }

      return;
    }
  }

  // RESET VERIFICATION

  void _resetVerification() {
    setState(() {
      _blinkCompleted = false;
      _leftCompleted = false;
      _rightCompleted = false;
      _straightCompleted = false;

      _livePersonVerified = false;

      _eyesWereClosed = false;

      _livenessMessage = 'Look at the camera and blink';
    });
  }

  Future<void> _capturePicture() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final XFile image = await controller.takePicture();

      debugPrint('Picture captured: ${image.path}');

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) {
          return Dialog(
            child: Image.file(
              File(image.path),
              fit: BoxFit.contain,
            ),
          );
        },
      );

      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(
          _processCameraImage,
        );
      }
    } catch (e) {
      debugPrint('Picture capture error: $e');

      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(
          _processCameraImage,
        );
      }
    }
  }

  // BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),

      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [

                // LIVE CAMERA
                Positioned.fill(child: CameraPreview(_cameraController!)),


                // FACE GUIDE
                Center(
                  child: Container(
                    width: 260,
                    height: 340,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _livePersonVerified
                            ? Colors.green
                            : Colors.white,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(160),
                    ),
                  ),
                ),

                // TOP STATUS
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: _buildTopStatus(),
                ),

                // BOTTOM INFO
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _buildBottomInfo(),
                ),
              ],
            ),
    );
  }

  // TOP STATUS
  Widget _buildTopStatus() {
    final Color statusColor;

    if (_livePersonVerified) {
      statusColor = Colors.green;
    } else if (_faceCount == 1) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _livePersonVerified
                    ? Icons.verified
                    : _faceCount == 1
                    ? Icons.face
                    : Icons.face_retouching_off,
                color: statusColor,
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  _faceStatus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            _livenessMessage,
            style: TextStyle(
              color: _livePersonVerified ? Colors.greenAccent : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // BOTTOM INFO
  Widget _buildBottomInfo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
      ),

      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // FACE
          // _sectionTitle('FACE'),
          //
          // _infoRow('Face', _faceStatus),
          //
          // _infoRow('Face Count', '$_faceCount'),
          //
          // const SizedBox(height: 6),


          // LANDMARKS
          // _sectionTitle('LANDMARKS'),
          //
          // _infoRow('Left Eye', _landmarkText(_leftEyeLandmark)),
          //
          // _infoRow('Right Eye', _landmarkText(_rightEyeLandmark)),
          //
          // _infoRow('Nose', _landmarkText(_noseLandmark)),
          //
          // const SizedBox(height: 6),


          // EYES
          // _sectionTitle('EYE DETECTION'),
          //
          // _infoRow('Left Eye', _leftEyeStatus),
          //
          // _infoRow('Left Probability', _formatProbability(_leftEyeProbability)),
          //
          // _infoRow('Right Eye', _rightEyeStatus),
          //
          // _infoRow(
          //   'Right Probability',
          //   _formatProbability(_rightEyeProbability),
          // ),
          //
          // const SizedBox(height: 6),


          // // SMILE
          // _sectionTitle('SMILE DETECTION'),
          //
          // _infoRow('Smile', _smileStatus),
          //
          // _infoRow('Probability', _formatProbability(_smileProbability)),
          //
          // const SizedBox(height: 6),


          // LIVENESS
          _sectionTitle('LIVENESS'),

          const SizedBox(height: 5),

          _buildLivenessSteps(),

          const SizedBox(height: 10),


          // VERIFY AGAIN
          if (_livePersonVerified)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _resetVerification,
                child: const Text('Verify Again'),
              ),
            ),
          // const SizedBox(height: 10),
          //
          // SizedBox(
          //   width: double.infinity,
          //   height: 50,
          //   child: ElevatedButton.icon(
          //     onPressed: _capturePicture,
          //     icon: const Icon(Icons.camera_alt),
          //     label: const Text('Take Picture'),
          //   ),
          // ),
        ],
      ),
    );
  }


  // LIVENESS STEPS
  Widget _buildLivenessSteps() {
    return Row(
      children: [
        _step('Blink', _blinkCompleted),

        _line(),

        _step('Left', _leftCompleted),

        _line(),

        _step('Right', _rightCompleted),

        _line(),

        _step('LIVE', _livePersonVerified),

        _line(),

        _step('Straight', _straightCompleted),
      ],
    );
  }

  Widget _step(String title, bool completed) {
    return Column(
      children: [
        Icon(
          completed ? Icons.check_circle : Icons.circle_outlined,
          color: completed ? Colors.green : Colors.white54,
          size: 25,
        ),

        const SizedBox(height: 3),

        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _line() {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        color: Colors.white30,
      ),
    );
  }

  // SECTION TITLE
  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }


  // INFO ROW
  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),

          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  // HELPERS
  String _landmarkText(bool detected) {
    return detected ? 'Detected ✓' : 'Not detected';
  }

  String _formatProbability(double? value) {
    if (value == null) {
      return '-';
    }

    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();

    _faceDetector.close();

    super.dispose();
  }
}
