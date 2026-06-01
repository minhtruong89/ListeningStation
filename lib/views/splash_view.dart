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
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Beautiful Glowing Logo Mockup
                  Container(
                    width: 80.0,
                    height: 80.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppStyles.accentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppStyles.primaryAccent.withValues(alpha: 0.5),
                          blurRadius: 20.0,
                          spreadRadius: 3.0,
                        )
                      ]
                    ),
                    child: const Icon(
                      Icons.hearing,
                      size: 40.0,
                      color: AppStyles.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 15.0),
                  
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
                  
                  const SizedBox(height: 19.0),
                  
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
                    const SizedBox(height: 19.0),
                  ],

                  if (vm.startupCheckLogs.isNotEmpty) ...[
                    Container(
                      constraints: const BoxConstraints(maxWidth: 800.0),
                      padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
                      margin: const EdgeInsets.symmetric(horizontal: 24.0),
                      decoration: AppStyles.glassDecoration(
                        borderColor: vm.errorMessage.isNotEmpty 
                            ? AppStyles.errorColor.withValues(alpha: 0.3) 
                            : AppStyles.glassCardBorder,
                      ),
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12.0,
                        mainAxisSpacing: 12.0,
                        childAspectRatio: 4.8,
                        children: vm.startupCheckLogs.map((log) {
                              final isPass = log.contains("PASS");
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                decoration: BoxDecoration(
                                  color: isPass 
                                      ? AppStyles.successColor.withValues(alpha: 0.05) 
                                      : AppStyles.errorColor.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(
                                    color: isPass 
                                        ? AppStyles.successColor.withValues(alpha: 0.2) 
                                        : AppStyles.errorColor.withValues(alpha: 0.2),
                                    width: 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isPass ? Icons.check_circle_outline : Icons.error_outline,
                                      color: isPass ? AppStyles.successColor : AppStyles.errorColor,
                                      size: 16.0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: Text(
                                        log,
                                        style: TextStyle(
                                          color: isPass ? AppStyles.textPrimary : AppStyles.errorColor,
                                          fontFamily: 'monospace',
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24.0),
                      ],

                  if (!vm.isValidating && vm.errorMessage.isNotEmpty) ...[
                    ElevatedButton.icon(
                      onPressed: () => vm.runStartupChecks(),
                      icon: const Icon(Icons.refresh, size: 18.0),
                      label: const Text("Thử Lại"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.primaryAccent,
                        foregroundColor: AppStyles.backgroundEnd,
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                      ),
                    )
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
