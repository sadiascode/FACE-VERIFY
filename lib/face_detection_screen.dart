import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  CameraController? _cameraController;

  late final FaceDetector _faceDetector;
  late final PoseDetector _poseDetector;

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

  String _livenessMessage = 'Look at the camera and blink';

  // Used to prevent the same closed-eye frame if it is close (don't say its blink)
  bool _eyesWereClosed = false;
  Face? _latestFace;
  Pose? _latestPose;

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

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
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

  // img convert
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final controller = _cameraController;

      if (controller == null) {
        return null;
      }

      final camera = controller.description;

      final rotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );

      if (rotation == null) {
        debugPrint('Invalid camera rotation: ${camera.sensorOrientation}');
        return null;
      }

      final format = InputImageFormatValue.fromRawValue(image.format.raw);

      if (format == null) {
        debugPrint('Invalid image format: ${image.format.raw}');
        return null;
      }

      if (image.planes.length != 1) {
        debugPrint('Unsupported plane count: ${image.planes.length}');
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
    } catch (e, stackTrace) {
      debugPrint('_convertCameraImage error: $e');
      debugPrint('$stackTrace');

      return null;
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

      // FACE DETECTION
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

      // POSE DETECTION
      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty) {
        final pose = poses.first;

        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];

        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

        if (leftShoulder != null && rightShoulder != null) {
          _latestPose = pose;

          debugPrint('==============================');
          debugPrint(
            'LEFT SHOULDER: '
            'x=${leftShoulder.x}, y=${leftShoulder.y}',
          );
          debugPrint(
            'RIGHT SHOULDER: '
            'x=${rightShoulder.x}, y=${rightShoulder.y}',
          );
          debugPrint('==============================');
        } else {
          _latestPose = null;
          debugPrint('Shoulder not detected');
        }
      } else {
        debugPrint('No pose detected');
      }

      _latestFace = faces.first;
      _handleFace(faces.first);
    } catch (e, stackTrace) {
      debugPrint('Face/Pose detection error: $e');
      debugPrint('$stackTrace');
    } finally {
      _isDetecting = false;
    }
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

      // if (!_livePersonVerified) {
      //   _livenessMessage = 'Place your face inside the frame';
      // }
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

          _livenessMessage = 'Right movement detected ✓\nNow look STRAIGHT';
        });

        debugPrint('================================');
        debugPrint('RIGHT MOVEMENT DETECTED');
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

        _capturePicture(face: face, pose: _latestPose);
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

      _eyesWereClosed = false;

      _livenessMessage = 'Look at the camera and blink';
    });
  }

  Future<void> _capturePicture({
    required Face face,
    required Pose? pose,
  }) async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final XFile imageFile = await controller.takePicture();

      debugPrint('Original picture: ${imageFile.path}');

      final croppedPath = await _cropHeadToShoulders(
        imageFile.path,
        face,
        pose,
      );

      debugPrint('Final cropped picture: $croppedPath');

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) {
          return Dialog(
            backgroundColor: Colors.black,
            child: Image.file(File(croppedPath), fit: BoxFit.contain),
          );
        },
      );

      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }
    } catch (e, stackTrace) {
      debugPrint('Picture capture error: $e');
      debugPrint('$stackTrace');

      if (mounted &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }
    }
  }

  // crop
  Future<String> _cropHeadToShoulders(
    String imagePath,
    Face face,
    Pose? pose,
  ) async {
    final bytes = await File(imagePath).readAsBytes();

    img.Image? original = img.decodeImage(bytes);

    if (original == null) {
      throw Exception('Unable to decode captured image');
    }

    // Correct the image orientation before using coordinates.
    original = img.bakeOrientation(original);

    final imageWidth = original.width;
    final imageHeight = original.height;

    debugPrint(
      'Captured image size: '
      '$imageWidth x $imageHeight',
    );

    final faceBox = face.boundingBox;

    double left = faceBox.left;
    double top = faceBox.top;
    double right = faceBox.right;
    double bottom = faceBox.bottom;

    double? leftShoulderX;
    double? leftShoulderY;
    double? rightShoulderX;
    double? rightShoulderY;

    bool isValidLandmark(PoseLandmark landmark) {
      return landmark.x.isFinite &&
          landmark.y.isFinite &&
          landmark.x >= 0 &&
          landmark.y >= 0 &&
          landmark.x <= imageWidth &&
          landmark.y <= imageHeight;
    }

    if (pose != null) {
      final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];

      final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

      if (leftShoulder != null &&
          rightShoulder != null &&
          isValidLandmark(leftShoulder) &&
          isValidLandmark(rightShoulder)) {
        leftShoulderX = leftShoulder.x;
        leftShoulderY = leftShoulder.y;

        rightShoulderX = rightShoulder.x;
        rightShoulderY = rightShoulder.y;

        final shoulderLeft = math.min(leftShoulder.x, rightShoulder.x);

        final shoulderRight = math.max(leftShoulder.x, rightShoulder.x);

        final shoulderY = math.max(leftShoulder.y, rightShoulder.y);

        final shoulderWidth = shoulderRight - shoulderLeft;

        if (shoulderWidth > 0) {
          /*
         * Include both shoulders horizontally.
         *
         * Use a moderate horizontal padding rather than padding
         * equal to the entire crop width.
         */
          final shoulderHorizontalPadding = shoulderWidth * 0.18;

          left = math.min(left, shoulderLeft - shoulderHorizontalPadding);

          right = math.max(right, shoulderRight + shoulderHorizontalPadding);

          /*
         * Stop shortly below the shoulder line.
         *
         * A value between 0.10 and 0.20 normally includes the
         * shoulders and a small area below the neck without
         * extending deeply into the chest.
         */
          final belowShoulderPadding = shoulderWidth * 0.08;

          bottom = math.max(bottom, shoulderY + belowShoulderPadding);
        }
      }
    }

    /*
   * Add space above the head.
   *
   * This is based on face height, not the full crop height, so it
   * does not create excessive space.
   */
    final faceHeight = faceBox.height;
    final topPadding = faceHeight * 0.35;

    top -= topPadding;

    /*
   * Add a small horizontal margin around the complete crop.
   * Do not use cropWidth as padding because that can double
   * the crop width and include too much background/body.
   */
    final currentWidth = right - left;
    final sidePadding = currentWidth * 0.08;

    left -= sidePadding;
    right += sidePadding;

    // Keep all coordinates inside the image.
    left = left.clamp(0.0, imageWidth.toDouble());
    top = top.clamp(0.0, imageHeight.toDouble());
    right = right.clamp(0.0, imageWidth.toDouble());
    bottom = bottom.clamp(0.0, imageHeight.toDouble());

    final x = left.floor();
    final y = top.floor();

    var width = (right - left).round();
    var height = (bottom - top).round();

    if (width <= 0 || height <= 0) {
      throw Exception('Invalid crop dimensions');
    }

    if (x + width > imageWidth) {
      width = imageWidth - x;
    }

    if (y + height > imageHeight) {
      height = imageHeight - y;
    }

    if (width <= 0 || height <= 0) {
      throw Exception('Crop is outside image bounds');
    }

    debugPrint('==============================');
    debugPrint('CROP RESULT');
    debugPrint('X: $x');
    debugPrint('Y: $y');
    debugPrint('WIDTH: $width');
    debugPrint('HEIGHT: $height');
    debugPrint('LEFT SHOULDER: $leftShoulderX, $leftShoulderY');
    debugPrint('RIGHT SHOULDER: $rightShoulderX, $rightShoulderY');
    debugPrint('==============================');

    final cropped = img.copyCrop(
      original,
      x: x,
      y: y,
      width: width,
      height: height,
    );

    final directory = File(imagePath).parent.path;

    final outputPath =
        '$directory/face_shoulders_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final outputFile = File(outputPath);

    await outputFile.writeAsBytes(
      Uint8List.fromList(img.encodeJpg(cropped, quality: 95)),
    );

    debugPrint('Cropped image saved: $outputPath');

    return outputPath;
  }

  // Future<String> _cropHeadToShoulders(
  //   String imagePath,
  //   Face face,
  //   Pose? pose,
  // ) async {
  //   final bytes = await File(imagePath).readAsBytes();
  //
  //   img.Image? original = img.decodeImage(bytes);
  //
  //   if (original == null) {
  //     throw Exception('Unable to decode captured image');
  //   }
  //
  //   // Apply camera EXIF orientation
  //   original = img.bakeOrientation(original);
  //
  //   final imageWidth = original.width;
  //   final imageHeight = original.height;
  //
  //   debugPrint(
  //     'Captured image size: '
  //     '$imageWidth x $imageHeight',
  //   );
  //
  //   final faceBox = face.boundingBox;
  //
  //   double left = faceBox.left;
  //   double top = faceBox.top;
  //   double right = faceBox.right;
  //   double bottom = faceBox.bottom;
  //
  //   if (pose != null) {
  //     final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
  //
  //     final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
  //
  //     if (leftShoulder != null && rightShoulder != null) {
  //       final shoulderLeft = leftShoulder.x < rightShoulder.x
  //           ? leftShoulder.x
  //           : rightShoulder.x;
  //
  //       final shoulderRight = leftShoulder.x > rightShoulder.x
  //           ? leftShoulder.x
  //           : rightShoulder.x;
  //
  //       final shoulderBottom = leftShoulder.y > rightShoulder.y
  //           ? leftShoulder.y
  //           : rightShoulder.y;
  //
  //       // Include both shoulders
  //       if (shoulderLeft < left) {
  //         left = shoulderLeft;
  //       }
  //
  //       if (shoulderRight > right) {
  //         right = shoulderRight;
  //       }
  //
  //       if (shoulderBottom > bottom) {
  //         bottom = shoulderBottom;
  //       }
  //     }
  //   }
  //
  //   // Padding
  //   final cropWidth = right - left;
  //   final cropHeight = bottom - top;
  //
  //   debugPrint('left: $left\ntop: $top\nright: $right\nbottom: $bottom');
  //
  //   final horizontalPadding = cropWidth;
  //   // final horizontalPadding = cropWidth * 0.20;
  //   final topPadding = cropHeight * 0.35;
  //   final bottomPadding = cropHeight * 0.75;
  //
  //   left -= horizontalPadding;
  //   right += horizontalPadding;
  //
  //   // Extra space above head
  //   top -= topPadding;
  //
  //   // Extra space below shoulders
  //   bottom += bottomPadding;
  //
  //   // Keep crop inside image
  //   left = left.clamp(0.0, imageWidth.toDouble());
  //
  //   top = top.clamp(0.0, imageHeight.toDouble());
  //
  //   right = right.clamp(0.0, imageWidth.toDouble());
  //
  //   bottom = bottom.clamp(0.0, imageHeight.toDouble());
  //
  //   final x = left.round();
  //   final y = top.round();
  //
  //   var width = (right - left).round();
  //   var height = (bottom - top).round();
  //
  //   if (width <= 0 || height <= 0) {
  //     throw Exception('Invalid crop dimensions');
  //   }
  //
  //   if (x + width > imageWidth) {
  //     width = imageWidth - x;
  //   }
  //
  //   if (y + height > imageHeight) {
  //     height = imageHeight - y;
  //   }
  //
  //   debugPrint('==============================');
  //   debugPrint('CROP RESULT');
  //   debugPrint('X: $x');
  //   debugPrint('Y: $y');
  //   debugPrint('WIDTH: $width');
  //   debugPrint('HEIGHT: $height');
  //   debugPrint('==============================');
  //
  //   final cropped = img.copyCrop(
  //     original,
  //     x: x,
  //     y: y,
  //     width: width,
  //     height: height,
  //   );
  //
  //   final directory = File(imagePath).parent.path;
  //
  //   final outputPath =
  //       '$directory/face_shoulders_'
  //       '${DateTime.now().millisecondsSinceEpoch}.jpg';
  //
  //   final outputFile = File(outputPath);
  //
  //   await outputFile.writeAsBytes(
  //     Uint8List.fromList(img.encodeJpg(cropped, quality: 95)),
  //   );
  //
  //   debugPrint('Cropped image saved: $outputPath');
  //
  //   return outputPath;
  // }

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
                        color: _straightCompleted ? Colors.green : Colors.white,
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

    if (_straightCompleted) {
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
                _straightCompleted
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
              color: _straightCompleted ? Colors.greenAccent : Colors.white,
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
          if (_straightCompleted)
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
    _poseDetector.close();

    super.dispose();
  }
}
