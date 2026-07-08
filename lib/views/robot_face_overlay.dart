import 'dart:async';
import 'package:flutter/material.dart';
import '../services/speech_service.dart';

class RobotFaceOverlay extends StatefulWidget {
  final Widget child;

  const RobotFaceOverlay({super.key, required this.child});

  @override
  State<RobotFaceOverlay> createState() => _RobotFaceOverlayState();
}

class _RobotFaceOverlayState extends State<RobotFaceOverlay> {
  bool _isVisible = SpeechService.flagSendSignalLocal;
  String _currentMode = "HELLO";
  Timer? _standbyTimer;

  @override
  void initState() {
    super.initState();
    SpeechService.faceAnimationNotifier.addListener(_onModeChanged);
    _startStandbyTimer();
  }

  @override
  void dispose() {
    SpeechService.faceAnimationNotifier.removeListener(_onModeChanged);
    _standbyTimer?.cancel();
    super.dispose();
  }

  void _onModeChanged() {
    if (!mounted) return;
    final newMode = SpeechService.faceAnimationNotifier.value;
    setState(() {
      _currentMode = newMode;
      _isVisible = SpeechService.flagSendSignalLocal;
    });

    _standbyTimer?.cancel();
    if (_currentMode == "SILIENCE" || _currentMode == "HELLO") {
      _startStandbyTimer();
    }
  }

  void _startStandbyTimer() {
    _standbyTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && (_currentMode == "SILIENCE" || _currentMode == "HELLO")) {
        SpeechService.sendAnimationFace("STAND BY");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.transparent,
            child: Center(
              child: Opacity(
                opacity: 0.8,
                child: RobotFaceWidget(mode: _currentMode),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RobotFaceWidget extends StatefulWidget {
  final String mode;

  const RobotFaceWidget({super.key, required this.mode});

  @override
  State<RobotFaceWidget> createState() => _RobotFaceWidgetState();
}

class _RobotFaceWidgetState extends State<RobotFaceWidget>
    with TickerProviderStateMixin {
  late AnimationController _talkingController;
  late AnimationController _blinkController;
  late AnimationController _sleepingController;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _talkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..repeat(reverse: true);

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _sleepingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startBlinking();
  }

  void _startBlinking() {
    _blinkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && widget.mode != "STAND BY") {
        _blinkController.forward().then((_) {
          _blinkController.reverse();
        });
      }
    });
  }

  @override
  void dispose() {
    _talkingController.dispose();
    _blinkController.dispose();
    _sleepingController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _talkingController,
        _blinkController,
        _sleepingController,
      ]),
      builder: (context, child) {
        return SizedBox(
          width: 640,
          height: 480,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(85),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: CustomPaint(
              painter: RobotFacePainter(
                mode: widget.mode,
                talkingValue: _talkingController.value,
                blinkValue: _blinkController.value,
                sleepingValue: _sleepingController.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

class RobotFacePainter extends CustomPainter {
  final String mode;
  final double talkingValue;
  final double blinkValue;
  final double sleepingValue;

  RobotFacePainter({
    required this.mode,
    required this.talkingValue,
    required this.blinkValue,
    required this.sleepingValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Responsive scale factor based on layout width (base width is 296)
    final double scale = size.width / 296.0;

    final cyanPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    final cyanStrokePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale;

    final pinkPaint = Paint()
      ..color = const Color(0xFFFF80AB)
      ..style = PaintingStyle.fill;

    // Dimensions helper
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // 1. Draw Cheeks (Pink soft ovals)
    final cheekWidth = 24.0 * scale;
    final cheekHeight = 14.0 * scale;
    final leftCheekCenter = Offset(centerX - 95 * scale, centerY + 30 * scale);
    final rightCheekCenter = Offset(centerX + 95 * scale, centerY + 30 * scale);

    canvas.drawOval(
      Rect.fromCenter(
        center: leftCheekCenter,
        width: cheekWidth,
        height: cheekHeight,
      ),
      pinkPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: rightCheekCenter,
        width: cheekWidth,
        height: cheekHeight,
      ),
      pinkPaint,
    );

    // 2. Draw Eyes
    final eyeWidth = 34.0 * scale;
    double leftEyeHeight = 58.0 * scale;
    double rightEyeHeight = 58.0 * scale;
    final leftEyeCenter = Offset(centerX - 60 * scale, centerY - 15 * scale);
    final rightEyeCenter = Offset(centerX + 60 * scale, centerY - 15 * scale);

    if (mode == "STAND BY") {
      // Sleeping mode: Curved lines (horizontal arcs)
      // Pulse height slightly with sleep breathing
      final double sleepBreathe = 2.0 * sleepingValue * scale;
      final double startY = centerY - 10 * scale + sleepBreathe;

      final Path sleepingLeftEye = Path()
        ..moveTo(leftEyeCenter.dx - 18 * scale, startY)
        ..quadraticBezierTo(
          leftEyeCenter.dx,
          startY + 15 * scale,
          leftEyeCenter.dx + 18 * scale,
          startY,
        );

      final Path sleepingRightEye = Path()
        ..moveTo(rightEyeCenter.dx - 18 * scale, startY)
        ..quadraticBezierTo(
          rightEyeCenter.dx,
          startY + 15 * scale,
          rightEyeCenter.dx + 18 * scale,
          startY,
        );

      canvas.drawPath(sleepingLeftEye, cyanStrokePaint);
      canvas.drawPath(sleepingRightEye, cyanStrokePaint);
    } else {
      // Normal/Blinking/Talking
      // Blink value shrinks vertical height to 0
      final double scaleY = 1.0 - blinkValue;
      canvas.drawOval(
        Rect.fromCenter(
          center: leftEyeCenter,
          width: eyeWidth,
          height: leftEyeHeight * scaleY,
        ),
        cyanPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: rightEyeCenter,
          width: eyeWidth,
          height: rightEyeHeight * scaleY,
        ),
        cyanPaint,
      );
    }

    // 3. Draw Mouth
    final mouthCenterY = centerY + 25 * scale;
    if (mode == "STAND BY") {
      // Standby mouth: Small horizontal line
      final Path standbyMouth = Path()
        ..moveTo(centerX - 10 * scale, mouthCenterY)
        ..lineTo(centerX + 10 * scale, mouthCenterY);
      canvas.drawPath(standbyMouth, cyanStrokePaint);
    } else if (mode == "SAY") {
      // Talking animation mouth: Open and close or scale w-mouth
      final double talkingHeight = (12.0 * talkingValue + 4.0) * scale;
      
      // Draw a talking mouth path that opens and closes
      final Path talkingMouth = Path();
      talkingMouth.moveTo(centerX - 18 * scale, mouthCenterY);
      // top lip
      talkingMouth.quadraticBezierTo(centerX - 9 * scale, mouthCenterY - talkingHeight, centerX, mouthCenterY);
      talkingMouth.quadraticBezierTo(centerX + 9 * scale, mouthCenterY - talkingHeight, centerX + 18 * scale, mouthCenterY);
      // bottom lip
      talkingMouth.quadraticBezierTo(centerX, mouthCenterY + talkingHeight, centerX - 18 * scale, mouthCenterY);
      
      canvas.drawPath(talkingMouth, cyanPaint);
    } else {
      // HELLO / SILIENCE Mode: Cute "w" cat-like mouth
      final Path catMouth = Path();
      
      // Left arc
      catMouth.moveTo(centerX - 16 * scale, mouthCenterY - 4 * scale);
      catMouth.quadraticBezierTo(
        centerX - 8 * scale,
        mouthCenterY + 8 * scale,
        centerX,
        mouthCenterY,
      );
      // Right arc
      catMouth.quadraticBezierTo(
        centerX + 8 * scale,
        mouthCenterY + 8 * scale,
        centerX + 16 * scale,
        mouthCenterY - 4 * scale,
      );

      canvas.drawPath(catMouth, cyanStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant RobotFacePainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.talkingValue != talkingValue ||
        oldDelegate.blinkValue != blinkValue ||
        oldDelegate.sleepingValue != sleepingValue;
  }
}
