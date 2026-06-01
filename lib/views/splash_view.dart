import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/main_viewmodel.dart';

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MainViewModel>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Beautiful Glowing Logo Mockup
              Container(
                width: 100.0,
                height: 100.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppStyles.accentGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppStyles.primaryAccent.withValues(alpha: 0.5),
                      blurRadius: 24.0,
                      spreadRadius: 4.0,
                    )
                  ]
                ),
                child: const Icon(
                  Icons.hearing,
                  size: 50.0,
                  color: AppStyles.textPrimary,
                ),
              ),
              const SizedBox(height: 32.0),
              
              const Text(
                "TRẠM LẮNG NGHE",
                style: AppStyles.titleHuge,
              ),
              const SizedBox(height: 8.0),
              const Text(
                "Hệ Thống Phê Duyệt Bảo Chứng Tự Động",
                style: TextStyle(
                  color: AppStyles.textSecondary,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 48.0),
              
              if (vm.isValidating) ...[
                const SizedBox(
                  width: 150.0,
                  child: LinearProgressIndicator(
                    color: AppStyles.primaryAccent,
                    backgroundColor: AppStyles.glassCardBorder,
                  ),
                ),
                const SizedBox(height: 16.0),
                const Text(
                  "Đang kiểm tra các thông số kỹ thuật...",
                  style: AppStyles.bodyMedium,
                ),
              ] else if (vm.errorMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  margin: const EdgeInsets.symmetric(horizontal: 48.0),
                  decoration: AppStyles.glassDecoration(borderColor: AppStyles.errorColor.withValues(alpha: 0.5)),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, color: AppStyles.errorColor, size: 40.0),
                      const SizedBox(height: 12.0),
                      Text(
                        vm.errorMessage,
                        style: AppStyles.bodyLarge.copyWith(color: AppStyles.errorColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton.icon(
                        onPressed: () => vm.runStartupChecks(),
                        icon: const Icon(Icons.refresh),
                        label: const Text("Thử Lại"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppStyles.primaryAccent,
                          foregroundColor: AppStyles.backgroundEnd,
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                      )
                    ],
                  ),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}
