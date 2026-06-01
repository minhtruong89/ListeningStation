import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

abstract class ICameraService {
  Future<void> initializeAsync();
  bool get hasCamera;
  CameraController? get controller;
  Future<void> startAsync();
  Future<void> stopAsync();
  List<CameraDescription> get cameras;
}

class CameraService implements ICameraService {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _hasCamera = false;

  @override
  bool get hasCamera => _hasCamera;

  @override
  CameraController? get controller => _controller;

  @override
  List<CameraDescription> get cameras => _cameras;

  @override
  Future<void> initializeAsync() async {
    try {
      _cameras = await availableCameras();
      _hasCamera = _cameras.isNotEmpty;
    } catch (e) {
      debugPrint("Error detecting cameras: \$e");
      _hasCamera = false;
    }
  }

  @override
  Future<void> startAsync() async {
    if (!_hasCamera) return;
    if (_controller != null) return;

    // Use rear camera as default on mobile, or front if rear is not available
    final selectedCamera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      debugPrint("Error starting camera: \$e");
      _controller = null;
    }
  }

  @override
  Future<void> stopAsync() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }
}
