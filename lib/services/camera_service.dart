import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

abstract class ICameraService {
  Future<void> initializeAsync();
  bool get hasCamera;
  bool get hasBackCamera;
  bool get hasExternalCamera;
  bool get useFrontCamera;
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
  bool get hasBackCamera {
    if (_cameras.isEmpty) return false;
    return _cameras.any((c) => c.lensDirection == CameraLensDirection.back);
  }

  @override
  bool get hasExternalCamera {
    if (_cameras.isEmpty) return false;
    return _cameras.any((c) => c.lensDirection == CameraLensDirection.external);
  }

  @override
  bool get useFrontCamera {
    if (_cameras.isEmpty) return false;
    final hasBackOrExternal = _cameras.any((c) =>
        c.lensDirection == CameraLensDirection.back ||
        c.lensDirection == CameraLensDirection.external);
    if (hasBackOrExternal) return false;
    return _cameras.any((c) => c.lensDirection == CameraLensDirection.front);
  }

  @override
  CameraController? get controller => _controller;

  @override
  List<CameraDescription> get cameras => _cameras;

  @override
  Future<void> initializeAsync() async {
    try {
      _cameras = await availableCameras();
      _hasCamera = _cameras.isNotEmpty;
      debugPrint("[CameraService] Detected ${_cameras.length} cameras:");
      for (var i = 0; i < _cameras.length; i++) {
        final c = _cameras[i];
        debugPrint("  Camera [$i]: name=${c.name}, lensDirection=${c.lensDirection}, sensorOrientation=${c.sensorOrientation}");
      }
    } catch (e) {
      debugPrint("Error detecting cameras: $e");
      _hasCamera = false;
    }
  }

  @override
  Future<void> startAsync() async {
    if (!_hasCamera) return;
    if (_controller != null) return;

    debugPrint("[CameraService] Starting camera search among ${_cameras.length} detected cameras...");

    for (var i = 0; i < _cameras.length; i++) {
      final camera = _cameras[i];
      debugPrint("[CameraService] Testing Camera [$i] (name=${camera.name}, direction=${camera.lensDirection})...");

      // Try all presets for maximum compatibility (some USB webcams only support their native resolution)
      for (var preset in [
        ResolutionPreset.high,
        ResolutionPreset.veryHigh,
        ResolutionPreset.max,
        ResolutionPreset.medium,
        ResolutionPreset.low,
      ]) {
        debugPrint("[CameraService]   Attempting with preset: $preset");
        _controller = CameraController(
          camera,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        try {
          await _controller!.initialize();
          debugPrint("[CameraService]   SUCCESS! Camera [$i] initialized with preset $preset");
          return; // Done, camera is running!
        } catch (e) {
          debugPrint("[CameraService]   FAILED: Camera [$i] preset $preset initialization error: $e");
          await _controller!.dispose();
          _controller = null;
        }
      }
    }

    debugPrint("[CameraService] ERROR: Tested all ${_cameras.length} cameras and none could be initialized.");
  }

  @override
  Future<void> stopAsync() async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }
}
