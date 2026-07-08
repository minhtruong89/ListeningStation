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
                opacity: 0.5,
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
        return Container(
          width: 320,
          height: 240,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(55),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 8,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(43),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
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
    final cyanPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    final cyanStrokePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final pinkPaint = Paint()
      ..color = const Color(0xFFFF80AB)
      ..style = PaintingStyle.fill;

    // Dimensions helper
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;

    // 1. Draw Cheeks (Pink soft ovals)
    final cheekWidth = 24.0;
    final cheekHeight = 14.0;
    final leftCheekCenter = Offset(centerX - 95, centerY + 30);
    final rightCheekCenter = Offset(centerX + 95, centerY + 30);

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
    final eyeWidth = 34.0;
    double leftEyeHeight = 58.0;
    double rightEyeHeight = 58.0;
    final leftEyeCenter = Offset(centerX - 60, centerY - 15);
    final rightEyeCenter = Offset(centerX + 60, centerY - 15);

    if (mode == "STAND BY") {
      // Sleeping mode: Curved lines (horizontal arcs)
      // Pulse height slightly with sleep breathing
      final double sleepBreathe = 2.0 * sleepingValue;
      final double startY = centerY - 10 + sleepBreathe;

      final Path sleepingLeftEye = Path()
        ..moveTo(leftEyeCenter.dx - 18, startY)
        ..quadraticBezierTo(
          leftEyeCenter.dx,
          startY + 15,
          leftEyeCenter.dx + 18,
          startY,
        );

      final Path sleepingRightEye = Path()
        ..moveTo(rightEyeCenter.dx - 18, startY)
        ..quadraticBezierTo(
          rightEyeCenter.dx,
          startY + 15,
          rightEyeCenter.dx + 18,
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
    final mouthCenterY = centerY + 25;
    if (mode == "STAND BY") {
      // Standby mouth: Small horizontal line
      final Path standbyMouth = Path()
        ..moveTo(centerX - 10, mouthCenterY)
        ..lineTo(centerX + 10, mouthCenterY);
      canvas.drawPath(standbyMouth, cyanStrokePaint);
    } else if (mode == "SAY") {
      // Talking animation mouth: Open and close or scale w-mouth
      final double talkingHeight = 12.0 * talkingValue + 4.0;
      
      // Draw a talking mouth path that opens and closes
      final Path talkingMouth = Path();
      talkingMouth.moveTo(centerX - 18, mouthCenterY);
      // top lip
      talkingMouth.quadraticBezierTo(centerX - 9, mouthCenterY - talkingHeight, centerX, mouthCenterY);
      talkingMouth.quadraticBezierTo(centerX + 9, mouthCenterY - talkingHeight, centerX + 18, mouthCenterY);
      // bottom lip
      talkingMouth.quadraticBezierTo(centerX, mouthCenterY + talkingHeight, centerX - 18, mouthCenterY);
      
      canvas.drawPath(talkingMouth, cyanPaint);
    } else {
      // HELLO / SILIENCE Mode: Cute "w" cat-like mouth
      final Path catMouth = Path();
      
      // Left arc
      catMouth.moveTo(centerX - 16, mouthCenterY - 4);
      catMouth.quadraticBezierTo(
        centerX - 8,
        mouthCenterY + 8,
        centerX,
        mouthCenterY,
      );
      // Right arc
      catMouth.quadraticBezierTo(
        centerX + 8,
        mouthCenterY + 8,
        centerX + 16,
        mouthCenterY - 4,
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
