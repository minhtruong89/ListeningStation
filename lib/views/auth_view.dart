import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import '../services/camera_service.dart';
import '../utils/styles.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final GlobalKey _previewBoundaryKey = GlobalKey();
  final TextEditingController _manualInputController = TextEditingController();
  MobileScannerController? _scannerController;
  bool _isDisposed = false;
  bool _hasAttemptedFallback = false;
  bool _hasAttemptedNoImageFallback = false;

  // Fallback Camera state variables
  late final ICameraService _cameraService;
  bool _useCameraPackageFallback = false;
  bool _isCapturingFallback = false;
  Timer? _fallbackScanTimer;
  bool _isConfirmButtonFocused = false;
  late final FocusNode _rotateCameraFocusNode;
  bool _isRotateCameraFocused = false;

  late final FocusNode _sliderExactFocus;
  late final FocusNode _sliderMinFocus;
  late final FocusNode _sliderMaxFocus;
  late final FocusNode _confirmButtonFocusNode;

  KeyEventResult _handleSliderKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (node == _sliderExactFocus || node == _sliderMinFocus) {
          // Topmost elements in popup: consume to prevent losing focus
          return KeyEventResult.handled;
        }
        node.previousFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }


  @override
  void initState() {
    super.initState();
    _cameraService = context.read<ICameraService>();
    _sliderExactFocus = FocusNode(onKeyEvent: _handleSliderKeyEvent);
    _sliderMinFocus = FocusNode(onKeyEvent: _handleSliderKeyEvent);
    _sliderMaxFocus = FocusNode(onKeyEvent: _handleSliderKeyEvent);
    _rotateCameraFocusNode = FocusNode();
    _rotateCameraFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isRotateCameraFocused = _rotateCameraFocusNode.hasFocus;
        });
      }
    });
    _confirmButtonFocusNode = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent) {
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.accept ||
            key == LogicalKeyboardKey.space) {
          final authVm = context.read<AuthViewModel>();
          final mainVm = context.read<MainViewModel>();
          authVm.confirmRangeAsync(() {
            mainVm.navigateTo(AppStage.conversation);
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          node.previousFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          // Bottommost element in popup: consume to prevent losing focus
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    });
    _confirmButtonFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isConfirmButtonFocused = _confirmButtonFocusNode.hasFocus;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _triggerCameraPackageFallback();
      _rotateCameraFocusNode.requestFocus();
    });
  }

  Future<void> _initAndStartScanner(CameraFacing facingToUse, {bool returnImage = true}) async {
    if (_isDisposed) return;

    debugPrint("[AuthView] Initializing MobileScannerController (facing: $facingToUse, returnImage: $returnImage)");
    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: facingToUse,
      cameraResolution: const Size(1280, 720), // Request 720p HD resolution for external USB webcams
      returnImage: returnImage,
      autoStart: false,
    );

    try {
      await controller.start();
      debugPrint("[AuthView] MobileScannerController started successfully!");
      if (!_isDisposed) {
        setState(() {
          _scannerController = controller;
        });
      }
    } catch (e) {
      debugPrint("[AuthView] Failed to start MobileScannerController (facing: $facingToUse, returnImage: $returnImage): $e");
      await controller.dispose();
      
      if (!_isDisposed) {
        if (!_hasAttemptedFallback) {
          _hasAttemptedFallback = true;
          final fallbackFacing = (facingToUse == CameraFacing.back) 
              ? CameraFacing.front 
              : CameraFacing.back;
          debugPrint("[AuthView] Retrying with fallback facing: $fallbackFacing");
          await _initAndStartScanner(fallbackFacing, returnImage: returnImage);
        } else if (!_hasAttemptedNoImageFallback && returnImage) {
          _hasAttemptedNoImageFallback = true;
          _hasAttemptedFallback = false; // Reset facing fallback for no-image attempt
          if (!mounted) return;
          final authVm = context.read<AuthViewModel>();
          await _initAndStartScanner(
            authVm.useFrontCamera ? CameraFacing.front : CameraFacing.back,
            returnImage: false,
          );
        } else if (!_useCameraPackageFallback) {
          _triggerCameraPackageFallback();
        }
      }
    }
  }

  void _startFallbackScanLoop() {
    _fallbackScanTimer?.cancel();
    _fallbackScanTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }
      final authVm = context.read<AuthViewModel>();
      if (authVm.isVerified || authVm.isRangePopupVisible || _isCapturingFallback) return;

      await _triggerGrabFrameAndScan();
    });
  }

  void _triggerCameraPackageFallback() {
    if (_useCameraPackageFallback || _isDisposed) return;
    debugPrint("[AuthView] Initializing standard camera package preview...");
    _useCameraPackageFallback = true;
    _fallbackScanTimer?.cancel();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_isDisposed) return;
      if (_scannerController != null) {
        await _scannerController!.dispose();
        setState(() {
          _scannerController = null;
        });
        // Give the OS driver some time to release the camera hardware lock completely
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      if (_isDisposed) return;
      await _cameraService.startAsync();
      if (mounted) {
        setState(() {});
        _startFallbackScanLoop();
      }
    });
  }

  Future<Uint8List?> _capturePreviewScreenshot() async {
    try {
      final boundary = _previewBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint("[AuthView] Error: RenderRepaintBoundary not found");
        return null;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint("[AuthView] Error capturing screenshot from boundary: $e");
      return null;
    }
  }



  Future<void> _triggerGrabFrameAndScan() async {
    if (_isCapturingFallback) return;
    if (_cameraService.controller == null || !_cameraService.controller!.value.isInitialized) return;

    final authVm = context.read<AuthViewModel>();

    if (mounted) {
      setState(() {
        _isCapturingFallback = true;
      });
    }

    String? tempFilePath;
    try {
      debugPrint("[AuthView-Fallback] Grabbing frame via viewport screenshot...");
      final pngBytes = await _capturePreviewScreenshot();
      if (pngBytes == null) {
        throw Exception("Failed to capture viewport screenshot");
      }

      img.Image? rgbImage = img.decodePng(pngBytes);
      if (rgbImage == null) {
        throw Exception("Failed to decode PNG bytes");
      }

      // Crop to the center 600x380 to match CCCD standard aspect ratio
      final int cropWidth = 600;
      final int cropHeight = 380;
      final int centerX = rgbImage.width ~/ 2;
      final int centerY = rgbImage.height ~/ 2;
      final int xStart = (centerX - cropWidth ~/ 2).clamp(0, rgbImage.width);
      final int yStart = (centerY - cropHeight ~/ 2).clamp(0, rgbImage.height);
      rgbImage = img.copyCrop(rgbImage, x: xStart, y: yStart, width: cropWidth, height: cropHeight);

      // Encode as JPEG
      final jpegBytes = img.encodeJpg(rgbImage);
      
      // Save to temp file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(jpegBytes);
      tempFilePath = tempFile.path;
      debugPrint("[AuthView-Fallback] Frame saved to temp file: $tempFilePath");

      // TODO TEST Copy to public directory for verification with unique timestamp
      /*try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final targetFile = File('${downloadDir.path}/rotated_scan_grab_$timestamp.jpg');
          await tempFile.copy(targetFile.path);
          debugPrint("[AuthView-Fallback] EXPORT SUCCESS: Saved grab image to: ${targetFile.path}");
        } else {
          final sdcardDir = Directory('/sdcard');
          if (await sdcardDir.exists()) {
            final targetFile = File('${sdcardDir.path}/rotated_scan_grab_$timestamp.jpg');
            await tempFile.copy(targetFile.path);
            debugPrint("[AuthView-Fallback] EXPORT SUCCESS: Saved grab image to: ${targetFile.path}");
          }
        }
      } catch (exportErr) {
        debugPrint("[AuthView-Fallback] Export grab image failed: $exportErr");
      }*/

      // 1. Analyze for Barcodes / QR Code using a temp instance of MobileScannerController
      debugPrint("[AuthView-Fallback] Starting QR detection on captured frame...");
      final tempController = MobileScannerController();
      final BarcodeCapture? barcodeCapture = await tempController.analyzeImage(tempFilePath);
      await tempController.dispose();

      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        final rawValue = barcodeCapture.barcodes.first.rawValue;
        if (rawValue != null) {
          debugPrint("[AuthView-Fallback] SUCCESS: QR Code found in image: $rawValue");
          await authVm.handleQrScanned(rawValue);
          
          try {
            await File(tempFilePath).delete();
          } catch (_) {}
          return;
        }
      }

      debugPrint("[AuthView-Fallback] No QR code detected in frame. Proceeding to OCR scanning...");

      // 2. Process live OCR using file path
      await authVm.handleOcrScanned(tempFilePath);

      // Clean up file
      try {
        await File(tempFilePath).delete();
      } catch (_) {}
    } catch (e) {
      debugPrint("[AuthView-Fallback] Error capturing / scanning image: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingFallback = false;
        });
      }
    }
  }

  bool _shouldRotate180() {
    if (_cameraService.cameras.isEmpty) return false;
    final firstCam = _cameraService.cameras.first;
    return firstCam.lensDirection == CameraLensDirection.external && firstCam.sensorOrientation == 90;
  }

  Widget _buildCameraWidget(Widget cameraWidget, int manualQuarterTurns) {
    int baseTurns = _shouldRotate180() ? 2 : 0;
    int totalTurns = (baseTurns + manualQuarterTurns) % 4;
    if (totalTurns > 0) {
      return RotatedBox(
        quarterTurns: totalTurns,
        child: cameraWidget,
      );
    }
    return cameraWidget;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fallbackScanTimer?.cancel();
    _manualInputController.dispose();
    _scannerController?.dispose();
    _sliderExactFocus.dispose();
    _sliderMinFocus.dispose();
    _sliderMaxFocus.dispose();
    _rotateCameraFocusNode.dispose();
    _confirmButtonFocusNode.dispose();
    _cameraService.stopAsync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authVm = context.watch<AuthViewModel>();
    final mainVm = context.read<MainViewModel>();
    final Size screenSize = MediaQuery.of(context).size;
    double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);
    scale = 1.5; // 1.5 - 1.2

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Landscape Side-by-Side Split View
              Focus(
                descendantsAreFocusable: !authVm.isRangePopupVisible,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // LEFT COLUMN: Viewfinder & Automatic Scanner
                    Expanded(
                      flex: 6,
                      child: Container(
                        decoration: AppStyles.glassDecoration(),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                             // 1. Camera QR Scanner Viewport or success overlay
                             authVm.isVerified
                                 ? Container(
                                     color: AppStyles.backgroundStart,
                                     child: Center(
                                       child: Column(
                                         mainAxisAlignment: MainAxisAlignment.center,
                                         children: [
                                           Icon(
                                             Icons.check_circle,
                                             color: AppStyles.successColor,
                                             size: 64.0 * scale,
                                           ),
                                           SizedBox(height: 16.0 * scale),
                                           Text(
                                             "Xác thực hoàn tất!",
                                             style: AppStyles.bodyLarge.copyWith(
                                               color: AppStyles.successColor,
                                               fontWeight: FontWeight.bold,
                                               fontSize: 18.0 * scale,
                                             ),
                                           ),
                                         ],
                                       ),
                                     ),
                                   )
                                 : _useCameraPackageFallback
                                     ? (_cameraService.controller != null &&
                                             _cameraService.controller!.value.isInitialized)
                                         ? RepaintBoundary(
                                             key: _previewBoundaryKey,
                                        child: AspectRatio(
                                          aspectRatio: 1.5,
                                          child: ClipRect(
                                            child: FittedBox(
                                              fit: BoxFit.cover,
                                              child: _buildCameraWidget(
                                                SizedBox(
                                                  width: _cameraService.controller!.value.previewSize?.width ?? 1280.0,
                                                  height: _cameraService.controller!.value.previewSize?.height ?? 720.0,
                                                  child: CameraPreview(_cameraService.controller!),
                                                ),
                                                authVm.cameraRotationQuarterTurns,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppStyles.backgroundStart,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: AppStyles.primaryAccent,
                                          ),
                                        ),
                                      )
                                : _scannerController == null
                                    ? Container(
                                        color: AppStyles.backgroundStart,
                                        child: const Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              color: AppStyles.primaryAccent,
                                            ),
                                            SizedBox(height: 16.0),
                                            Text(
                                              "Đang chuẩn bị camera...",
                                              style: AppStyles.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      )
                                    : AspectRatio(
                                        aspectRatio: 1.5,
                                        child: ClipRect(
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            child: _buildCameraWidget(
                                              SizedBox(
                                                width: 1280.0,
                                                height: 720.0,
                                                child: MobileScanner(
                                                  controller: _scannerController!,
                                                  onDetect: (capture) {
                                                    // 1. Process Barcodes / QR Code
                                                    final List<Barcode> barcodes = capture.barcodes;
                                                    for (final barcode in barcodes) {
                                                      if (barcode.rawValue != null) {
                                                        authVm.handleQrScanned(barcode.rawValue!);
                                                        break;
                                                      }
                                                    }

                                                    // 2. Process OCR from current image frame on-the-fly (only if image data is returned)
                                                    final image = capture.image;
                                                    final size = capture.size;
                                                    if (image != null) {
                                                      try {
                                                        final inputImage = InputImage.fromBytes(
                                                          bytes: image,
                                                          metadata: InputImageMetadata(
                                                            size: Size(size.width, size.height),
                                                            rotation: InputImageRotation.rotation0deg, // standard camera frame angle
                                                            format: InputImageFormat.nv21,
                                                            bytesPerRow: size.width.toInt(),
                                                          ),
                                                        );
                                                        authVm.handleOcrImageFrame(inputImage);
                                                      } catch (e) {
                                                        debugPrint("[AuthView] Error converting live frame to InputImage for OCR: $e");
                                                      }
                                                    }
                                                  },
                                                  errorBuilder: (context, error, child) {
                                                    debugPrint("[AuthView] MobileScanner error: ${error.errorCode}, code: ${error.errorDetails?.code}, msg: ${error.errorDetails?.message}, details: ${error.errorDetails?.details}");
                                                    
                                                    // If we get genericError during live streaming and returnImage is true,
                                                    // try falling back to returnImage: false (no raw frame byte delivery to Flutter)
                                                    if (error.errorCode == MobileScannerErrorCode.genericError) {
                                                      if (!_hasAttemptedNoImageFallback) {
                                                        _hasAttemptedNoImageFallback = true;
                                                        final useFront = authVm.useFrontCamera;
                                                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                                                          if (_isDisposed) return;
                                                          debugPrint("[AuthView] Caught genericError. Re-initializing with returnImage = false...");
                                                          if (_scannerController != null) {
                                                            await _scannerController!.dispose();
                                                            setState(() {
                                                              _scannerController = null;
                                                            });
                                                          }
                                                          await _initAndStartScanner(
                                                            useFront ? CameraFacing.front : CameraFacing.back,
                                                            returnImage: false,
                                                          );
                                                        });
                                                        
                                                        return Container(
                                                          color: AppStyles.backgroundStart,
                                                          child: const Center(
                                                            child: CircularProgressIndicator(
                                                              color: AppStyles.primaryAccent,
                                                            ),
                                                          ),
                                                        );
                                                      } else if (!_useCameraPackageFallback) {
                                                        _triggerCameraPackageFallback();
                                                        return Container(
                                                          color: AppStyles.backgroundStart,
                                                          child: const Center(
                                                            child: CircularProgressIndicator(
                                                              color: AppStyles.primaryAccent,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    }

                                                    return Container(
                                                      color: AppStyles.backgroundStart,
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(16.0),
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            const Icon(Icons.videocam_off, color: AppStyles.errorColor, size: 48.0),
                                                            const SizedBox(height: 12.0),
                                                            Text(
                                                              "Lỗi camera: ${error.errorCode.name}",
                                                              style: AppStyles.bodyMedium.copyWith(color: AppStyles.errorColor, fontWeight: FontWeight.bold),
                                                              textAlign: TextAlign.center,
                                                            ),
                                                            if (error.errorDetails != null) ...[
                                                              const SizedBox(height: 8.0),
                                                              Text(
                                                                "Code: ${error.errorDetails?.code}\nMsg: ${error.errorDetails?.message}\nDetails: ${error.errorDetails?.details}",
                                                                style: AppStyles.caption.copyWith(color: AppStyles.textSecondary),
                                                                textAlign: TextAlign.center,
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              authVm.cameraRotationQuarterTurns,
                                            ),
                                          ),
                                        ),
                                      ),

                            // 2. Cyan Scanner Alignment Guides Overlay
                            Container(
                              width: 300.0 * scale,
                              height: 190.0 * scale,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppStyles.primaryAccent,
                                  width: 2.5 * scale,
                                ),
                                borderRadius: BorderRadius.circular(16.0 * scale),
                              ),
                            ),
                            
                            // 3. Scan Sweep Animation Indicator
                            Positioned(
                              top: 60.0 * scale,
                              child: Container(
                                width: 430.0 * scale,
                                height: 3.0 * scale,
                                decoration: BoxDecoration(
                                  color: AppStyles.primaryAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppStyles.primaryAccent.withValues(alpha: 0.8),
                                      blurRadius: 8.0 * scale,
                                      spreadRadius: 2.0 * scale,
                                    )
                                  ]
                                ),
                              ),
                            ),

                            // 4. Instructions
                            Positioned(
                              bottom: 24.0 * scale,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 8.0 * scale),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20.0 * scale),
                                ),
                                child: Text(
                                  "Căn chỉnh QR CCCD hoặc thẻ của bạn vào ô quét",
                                  style: AppStyles.bodyMedium.copyWith(
                                    color: AppStyles.primaryAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.0 * scale,
                                  ),
                                ),
                              ),
                            ),

                            // 5. Fallback analyzer status overlay
                            if (_isCapturingFallback)
                              Container(
                                color: Colors.black45,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        color: AppStyles.primaryAccent,
                                        strokeWidth: 4.0 * scale,
                                      ),
                                      SizedBox(height: 16.0 * scale),
                                      Text(
                                        "Đang phân tích hình ảnh...",
                                        style: AppStyles.bodyMedium.copyWith(
                                          color: AppStyles.primaryAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.0 * scale,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // 6. Camera rotation toggle button (floating overlay)
                            Positioned(
                              top: 16.0 * scale,
                              right: 16.0 * scale,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  focusNode: _rotateCameraFocusNode,
                                  onTap: () {
                                    authVm.cycleCameraRotation();
                                  },
                                  borderRadius: BorderRadius.circular(20.0 * scale),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 14.0 * scale, vertical: 10.0 * scale),
                                    decoration: BoxDecoration(
                                      color: _isRotateCameraFocused 
                                          ? AppStyles.primaryAccent 
                                          : Colors.black54,
                                      borderRadius: BorderRadius.circular(20.0 * scale),
                                      border: Border.all(
                                        color: _isRotateCameraFocused ? Colors.white : AppStyles.primaryAccent.withValues(alpha: 0.5),
                                        width: _isRotateCameraFocused ? 2.5 * scale : 1.0,
                                      ),
                                      boxShadow: _isRotateCameraFocused
                                          ? [
                                              BoxShadow(
                                                color: AppStyles.primaryAccent.withValues(alpha: 0.6),
                                                blurRadius: 12.0 * scale,
                                                spreadRadius: 2.0 * scale,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.rotate_right, 
                                          color: _isRotateCameraFocused ? AppStyles.backgroundEnd : AppStyles.primaryAccent, 
                                          size: 18.0 * scale,
                                        ),
                                        SizedBox(width: 6.0 * scale),
                                        Text(
                                          "Xoay Camera",
                                          style: TextStyle(
                                            color: _isRotateCameraFocused ? AppStyles.backgroundEnd : AppStyles.textPrimary,
                                            fontSize: 12.0 * scale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24.0),

                    // RIGHT COLUMN: Sign-In status and Manual input panel
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // App Title Header
                            Row(
                              children: [
                                Icon(Icons.hearing, color: AppStyles.primaryAccent, size: 28.0 * scale),
                                SizedBox(width: 8.0 * scale),
                                Text(
                                  "TRẠM LẮNG NGHE",
                                  style: AppStyles.titleLarge.copyWith(fontSize: 24.0 * scale),
                                ),
                              ],
                            ),
                            SizedBox(height: 12.0 * scale),
                            
                            // Stage Verification Info Card
                            Container(
                              padding: EdgeInsets.all(12.0 * scale),
                              decoration: AppStyles.glassDecoration(
                                borderColor: AppStyles.primaryAccent.withValues(alpha: 0.3),
                                radius: 16.0 * scale,
                              ),
                              child: Text(
                                authVm.verificationInfoText,
                                style: AppStyles.bodyMedium.copyWith(
                                  color: AppStyles.primaryAccent,
                                  fontSize: 14.0 * scale,
                                ),
                              ),
                            ),
                            SizedBox(height: 12.0 * scale),

                            // Verified list of operators
                            Container(
                              height: 150.0 * scale, // Fixed constraint height for scroll list
                              padding: EdgeInsets.all(12.0 * scale),
                              decoration: AppStyles.glassDecoration(radius: 16.0 * scale),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Người Bảo Chứng Đã Xác Nhận",
                                    style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                                  ),
                                  SizedBox(height: 8.0 * scale),
                                  Expanded(
                                    child: authVm.verifiedOperatorsDisplay.isEmpty
                                        ? Center(
                                            child: Text(
                                              "Chưa có người bảo chứng nào quét thẻ",
                                              style: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: authVm.verifiedOperatorsDisplay.length,
                                            itemBuilder: (context, index) {
                                              final op = authVm.verifiedOperatorsDisplay[index];
                                              return Container(
                                                margin: EdgeInsets.only(bottom: 6.0 * scale),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 12.0 * scale,
                                                  vertical: 8.0 * scale,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppStyles.glassCardBorder.withValues(alpha: 0.3),
                                                  borderRadius: BorderRadius.circular(8.0 * scale),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.check_circle, color: AppStyles.successColor, size: 18.0 * scale),
                                                    SizedBox(width: 8.0 * scale),
                                                    Expanded(
                                                      child: Text(
                                                        op.displayName,
                                                        style: AppStyles.bodyMedium.copyWith(
                                                          color: AppStyles.textPrimary,
                                                          fontSize: 14.0 * scale,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      op.dailyCountText,
                                                      style: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12.0 * scale),

                            // Status text container
                            if (authVm.ruleStatusText.isNotEmpty) ...[
                              Container(
                                padding: EdgeInsets.all(10.0 * scale),
                                decoration: AppStyles.glassDecoration(
                                  radius: 16.0 * scale,
                                  borderColor: authVm.ruleStatusText.contains("Thành công")
                                      ? AppStyles.successColor.withValues(alpha: 0.5)
                                      : AppStyles.errorColor.withValues(alpha: 0.5),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      authVm.ruleStatusText.contains("Thành công") ? Icons.check : Icons.warning_amber_outlined,
                                      color: authVm.ruleStatusText.contains("Thành công") ? AppStyles.successColor : AppStyles.errorColor,
                                      size: 18.0 * scale,
                                    ),
                                    SizedBox(width: 8.0 * scale),
                                    Expanded(
                                      child: Text(
                                        authVm.ruleStatusText,
                                        style: AppStyles.bodyMedium.copyWith(
                                          color: authVm.ruleStatusText.contains("Thành công") ? AppStyles.successColor : AppStyles.errorColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.0 * scale,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12.0 * scale),
                            ],

                            // Manual CCCD Input
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: AppStyles.glassDecoration(radius: 12.0 * scale),
                                    padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                                    child: TextField(
                                      controller: _manualInputController,
                                      enabled: !authVm.isRangePopupVisible,
                                      style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                                      decoration: InputDecoration(
                                        hintText: "Nhập số CCCD thủ công",
                                        hintStyle: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                                        border: InputBorder.none,
                                      ),
                                      keyboardType: TextInputType.number,
                                      onSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          authVm.handleManualInput(val.trim());
                                          _manualInputController.clear();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12.0 * scale),
                                SizedBox(
                                  height: 45.0 * scale,
                                  child: ElevatedButton(
                                    onPressed: authVm.isRangePopupVisible ? null : () {
                                      final val = _manualInputController.text;
                                      if (val.trim().isNotEmpty) {
                                        authVm.handleManualInput(val.trim());
                                        _manualInputController.clear();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppStyles.primaryAccent,
                                      foregroundColor: AppStyles.backgroundEnd,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0 * scale)),
                                      elevation: 0.0,
                                    ),
                                    child: Icon(Icons.send, size: 18.0 * scale),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

              // OVERLAY DIALOG: Financial limits sliding inputs popup
              if (authVm.isRangePopupVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 550.0 * scale,
                      padding: EdgeInsets.all(20.0 * scale),
                      decoration: AppStyles.glassDecoration(
                        borderColor: AppStyles.primaryAccent,
                        radius: 16.0 * scale,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.tune, color: AppStyles.primaryAccent, size: 24.0 * scale),
                                SizedBox(width: 12.0 * scale),
                                Text(
                                  "THIẾT LẬP HẠN MỨC PHÊ DUYỆT",
                                  style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                                ),
                              ],
                            ),
                            SizedBox(height: 6.0 * scale),
                            Text(
                              "Thiết lập khoảng giới hạn tiền được duyệt cho ca này.",
                              style: AppStyles.caption.copyWith(fontSize: 12.0 * scale),
                            ),
                            SizedBox(height: 16.0 * scale),

                            if (authVm.flagOperatorExact) ...[
                              // Hạn mức Đề ra Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Hạn mức Đề ra:",
                                    style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale),
                                  ),
                                  Text(
                                    "${_formatCurrency(authVm.caseOperatorExact)} VNĐ",
                                    style: AppStyles.bodyLarge.copyWith(
                                      color: AppStyles.primaryAccent,
                                      fontSize: 16.0 * scale,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppStyles.primaryAccent,
                                  inactiveTrackColor: AppStyles.glassCardBorder,
                                  thumbColor: AppStyles.primaryAccent,
                                  overlayColor: AppStyles.primaryAccent.withAlpha(32),
                                  trackHeight: 4.0 * scale,
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10.0 * scale),
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 20.0 * scale),
                                ),
                                child: Slider(
                                  autofocus: true,
                                  focusNode: _sliderExactFocus,
                                  value: authVm.caseOperatorExact,
                                  min: 0.0,
                                  max: authVm.maxTransactionAmount,
                                  divisions: 20,
                                  onChanged: (val) {
                                    authVm.caseOperatorExact = val;
                                  },
                                ),
                              ),
                            ] else ...[
                              // Min Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Hạn mức Tối thiểu (Min):",
                                    style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale),
                                  ),
                                  Text(
                                    "${_formatCurrency(authVm.caseOperatorMin)} VNĐ",
                                    style: AppStyles.bodyLarge.copyWith(
                                      color: AppStyles.primaryAccent,
                                      fontSize: 16.0 * scale,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppStyles.primaryAccent,
                                  inactiveTrackColor: AppStyles.glassCardBorder,
                                  thumbColor: AppStyles.primaryAccent,
                                  overlayColor: AppStyles.primaryAccent.withAlpha(32),
                                  trackHeight: 4.0 * scale,
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10.0 * scale),
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 20.0 * scale),
                                ),
                                child: Slider(
                                  autofocus: true,
                                  focusNode: _sliderMinFocus,
                                  value: authVm.caseOperatorMin,
                                  min: 0.0,
                                  max: authVm.maxTransactionAmount,
                                  divisions: 20,
                                  onChanged: (val) {
                                    authVm.caseOperatorMin = val;
                                  },
                                ),
                              ),
                              SizedBox(height: 8.0 * scale),

                              // Max Slider
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Hạn mức Tối đa (Max):",
                                    style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale),
                                  ),
                                  Text(
                                    "${_formatCurrency(authVm.caseOperatorMax)} VNĐ",
                                    style: AppStyles.bodyLarge.copyWith(
                                      color: AppStyles.secondaryAccent,
                                      fontSize: 16.0 * scale,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppStyles.secondaryAccent,
                                  inactiveTrackColor: AppStyles.glassCardBorder,
                                  thumbColor: AppStyles.secondaryAccent,
                                  overlayColor: AppStyles.secondaryAccent.withAlpha(32),
                                  trackHeight: 4.0 * scale,
                                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10.0 * scale),
                                  overlayShape: RoundSliderOverlayShape(overlayRadius: 20.0 * scale),
                                ),
                                child: Slider(
                                  focusNode: _sliderMaxFocus,
                                  value: authVm.caseOperatorMax,
                                  min: 0.0,
                                  max: authVm.maxTransactionAmount,
                                  divisions: 20,
                                  onChanged: (val) {
                                    authVm.caseOperatorMax = val;
                                  },
                                ),
                              ),
                            ],
                            SizedBox(height: 20.0 * scale),

                            // Action confirm
                            SizedBox(
                              height: 48.0 * scale,
                              child: ElevatedButton(
                                focusNode: _confirmButtonFocusNode,
                                onPressed: () {
                                  authVm.confirmRangeAsync(() {
                                    mainVm.navigateTo(AppStage.conversation);
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isConfirmButtonFocused ? AppStyles.successColor : AppStyles.successColor.withValues(alpha: 0.7),
                                  foregroundColor: AppStyles.backgroundEnd,
                                  side: _isConfirmButtonFocused ? BorderSide(color: Colors.white, width: 3.5 * scale) : null,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0 * scale)),
                                  elevation: _isConfirmButtonFocused ? 12.0 : 0.0,
                                ),
                                child: Text(
                                  "XÁC NHẬN VÀ BẮT ĐẦU PHỎNG VẤN",
                                  style: AppStyles.bodyLarge.copyWith(
                                    fontSize: 16.0 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  String _formatCurrency(double amount) {
    String val = amount.toStringAsFixed(0);
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return val.replaceAllMapped(reg, (Match m) => "${m[1]},");
  }
}
