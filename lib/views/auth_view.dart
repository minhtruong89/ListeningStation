import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final TextEditingController _manualInputController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    returnImage: true,
  );

  @override
  void dispose() {
    _manualInputController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authVm = context.watch<AuthViewModel>();
    final mainVm = context.read<MainViewModel>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Landscape Side-by-Side Split View
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // LEFT COLUMN: Viewfinder & Automatic Scanner
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: AppStyles.glassDecoration(),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. Camera QR Scanner Viewport
                            MobileScanner(
                              controller: _scannerController,
                              onDetect: (capture) {
                                // 1. Process Barcodes / QR Code
                                final List<Barcode> barcodes = capture.barcodes;
                                for (final barcode in barcodes) {
                                  if (barcode.rawValue != null) {
                                    authVm.handleQrScanned(barcode.rawValue!);
                                    break;
                                  }
                                }

                                // 2. Process OCR from current image frame on-the-fly
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
                                return Container(
                                  color: AppStyles.backgroundStart,
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.videocam_off, color: AppStyles.textSecondary, size: 48.0),
                                      SizedBox(height: 12.0),
                                      Text(
                                        "Đang chuẩn bị camera...",
                                        style: AppStyles.bodyMedium,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // 2. Cyan Scanner Alignment Guides Overlay
                            Container(
                              width: 250.0,
                              height: 250.0,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppStyles.primaryAccent,
                                  width: 2.5,
                                ),
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                            ),
                            
                            // 3. Scan Sweep Animation Indicator
                            Positioned(
                              top: 60.0,
                              child: Container(
                                width: 260.0,
                                height: 3.0,
                                decoration: BoxDecoration(
                                  color: AppStyles.primaryAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppStyles.primaryAccent.withValues(alpha: 0.8),
                                      blurRadius: 8.0,
                                      spreadRadius: 2.0,
                                    )
                                  ]
                                ),
                              ),
                            ),

                            // 4. Instructions
                            Positioned(
                              bottom: 24.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: const Text(
                                  "Căn chỉnh QR CCCD hoặc thẻ của bạn vào ô quét",
                                  style: AppStyles.bodyMedium,
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
                      flex: 5,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // App Title Header
                            const Row(
                              children: [
                                Icon(Icons.hearing, color: AppStyles.primaryAccent, size: 28.0),
                                SizedBox(width: 8.0),
                                Text(
                                  "TRẠM LẮNG NGHE",
                                  style: AppStyles.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            
                            // Stage Verification Info Card
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: AppStyles.glassDecoration(borderColor: AppStyles.primaryAccent.withValues(alpha: 0.3)),
                              child: Text(
                                authVm.verificationInfoText,
                                style: AppStyles.bodyMedium.copyWith(color: AppStyles.primaryAccent),
                              ),
                            ),
                            const SizedBox(height: 12.0),

                            // Verified list of operators
                            Container(
                              height: 150.0, // Fixed constraint height for scroll list
                              padding: const EdgeInsets.all(12.0),
                              decoration: AppStyles.glassDecoration(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Người Bảo Chứng Đã Xác Nhận", style: AppStyles.bodyLarge),
                                  const SizedBox(height: 8.0),
                                  Expanded(
                                    child: authVm.verifiedOperatorsDisplay.isEmpty
                                        ? const Center(
                                            child: Text(
                                              "Chưa có người bảo chứng nào quét thẻ",
                                              style: AppStyles.caption,
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: authVm.verifiedOperatorsDisplay.length,
                                            itemBuilder: (context, index) {
                                              final op = authVm.verifiedOperatorsDisplay[index];
                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 6.0),
                                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                                decoration: BoxDecoration(
                                                  color: AppStyles.glassCardBorder.withValues(alpha: 0.3),
                                                  borderRadius: BorderRadius.circular(8.0),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.check_circle, color: AppStyles.successColor, size: 18.0),
                                                    const SizedBox(width: 8.0),
                                                    Expanded(
                                                      child: Text(op.displayName, style: AppStyles.bodyMedium.copyWith(color: AppStyles.textPrimary)),
                                                    ),
                                                    Text(op.dailyCountText, style: AppStyles.caption),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12.0),

                            // Status text container
                            if (authVm.ruleStatusText.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(10.0),
                                decoration: AppStyles.glassDecoration(
                                  borderColor: authVm.ruleStatusText.contains("Thành công")
                                      ? AppStyles.successColor.withValues(alpha: 0.5)
                                      : AppStyles.errorColor.withValues(alpha: 0.5),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      authVm.ruleStatusText.contains("Thành công") ? Icons.check : Icons.warning_amber_outlined,
                                      color: authVm.ruleStatusText.contains("Thành công") ? AppStyles.successColor : AppStyles.errorColor,
                                      size: 18.0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: Text(
                                        authVm.ruleStatusText,
                                        style: AppStyles.bodyMedium.copyWith(
                                          color: authVm.ruleStatusText.contains("Thành công") ? AppStyles.successColor : AppStyles.errorColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12.0),
                            ],

                            // Manual CCCD Input
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: AppStyles.glassDecoration(radius: 12.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: TextField(
                                      controller: _manualInputController,
                                      style: AppStyles.bodyLarge,
                                      decoration: const InputDecoration(
                                        hintText: "Nhập số CCCD thủ công",
                                        hintStyle: AppStyles.caption,
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
                                const SizedBox(width: 12.0),
                                SizedBox(
                                  height: 45.0,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      final val = _manualInputController.text;
                                      if (val.trim().isNotEmpty) {
                                        authVm.handleManualInput(val.trim());
                                        _manualInputController.clear();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppStyles.primaryAccent,
                                      foregroundColor: AppStyles.backgroundEnd,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                      elevation: 0.0,
                                    ),
                                    child: const Icon(Icons.send),
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

              // OVERLAY DIALOG: Financial limits sliding inputs popup
              if (authVm.isRangePopupVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 550.0,
                      padding: const EdgeInsets.all(20.0),
                      decoration: AppStyles.glassDecoration(borderColor: AppStyles.primaryAccent),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.tune, color: AppStyles.primaryAccent, size: 24.0),
                                SizedBox(width: 12.0),
                                Text("THIẾT LẬP HẠN MỨC CA PHÊ DUYỆT", style: AppStyles.bodyLarge),
                              ],
                            ),
                            const SizedBox(height: 6.0),
                            const Text(
                              "Thiết lập khoảng giới hạn tiền được duyệt cho ca này.",
                              style: AppStyles.caption,
                            ),
                            const SizedBox(height: 16.0),

                            // Min Slider
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Hạn mức Tối thiểu (Min):", style: AppStyles.bodyMedium),
                                Text(
                                  "${_formatCurrency(authVm.caseOperatorMin)} VNĐ",
                                  style: AppStyles.bodyLarge.copyWith(color: AppStyles.primaryAccent),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppStyles.primaryAccent,
                                inactiveTrackColor: AppStyles.glassCardBorder,
                                thumbColor: AppStyles.primaryAccent,
                                overlayColor: AppStyles.primaryAccent.withAlpha(32),
                              ),
                              child: Slider(
                                value: authVm.caseOperatorMin,
                                min: 0.0,
                                max: authVm.maxTransactionAmount,
                                divisions: 20,
                                onChanged: (val) {
                                  authVm.caseOperatorMin = val;
                                },
                              ),
                            ),
                            const SizedBox(height: 8.0),

                            // Max Slider
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Hạn mức Tối đa (Max):", style: AppStyles.bodyMedium),
                                Text(
                                  "${_formatCurrency(authVm.caseOperatorMax)} VNĐ",
                                  style: AppStyles.bodyLarge.copyWith(color: AppStyles.secondaryAccent),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppStyles.secondaryAccent,
                                inactiveTrackColor: AppStyles.glassCardBorder,
                                thumbColor: AppStyles.secondaryAccent,
                                overlayColor: AppStyles.secondaryAccent.withAlpha(32),
                              ),
                              child: Slider(
                                value: authVm.caseOperatorMax,
                                min: 0.0,
                                max: authVm.maxTransactionAmount,
                                divisions: 20,
                                onChanged: (val) {
                                  authVm.caseOperatorMax = val;
                                },
                              ),
                            ),
                            const SizedBox(height: 20.0),

                            // Action confirm
                            SizedBox(
                              height: 48.0,
                              child: ElevatedButton(
                                onPressed: () {
                                  authVm.confirmRangeAsync(() {
                                    mainVm.navigateTo(AppStage.conversation);
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppStyles.successColor,
                                  foregroundColor: AppStyles.backgroundEnd,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                  elevation: 0.0,
                                ),
                                child: const Text("XÁC NHẬN VÀ BẮT ĐẦU PHỎNG VẤN", style: AppStyles.bodyLarge),
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
