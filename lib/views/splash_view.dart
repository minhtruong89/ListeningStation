import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/main_viewmodel.dart';

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MainViewModel>();
    final Size screenSize = MediaQuery.of(context).size;
    double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);
    scale = 1.9;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0 * scale),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Beautiful Glowing Logo Mockup
                  Container(
                    width: 80.0 * scale,
                    height: 80.0 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppStyles.accentGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppStyles.primaryAccent.withValues(alpha: 0.5),
                          blurRadius: 20.0 * scale,
                          spreadRadius: 3.0 * scale,
                        )
                      ]
                    ),
                    child: Icon(
                      Icons.hearing,
                      size: 40.0 * scale,
                      color: AppStyles.textPrimary,
                    ),
                  ),
                  SizedBox(height: 15.0 * scale),
                  
                  Text(
                    "TRẠM LẮNG NGHE",
                    style: AppStyles.titleHuge.copyWith(fontSize: 32.0 * scale),
                  ),
                  SizedBox(height: 8.0 * scale),
                  Text(
                    "Hệ Thống Phê Duyệt Bảo Chứng Tự Động",
                    style: TextStyle(
                      color: AppStyles.textSecondary,
                      fontSize: 16.0 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  
                  SizedBox(height: 19.0 * scale),
                  
                  if (vm.isValidating) ...[
                    SizedBox(
                      width: 150.0 * scale,
                      child: LinearProgressIndicator(
                        color: AppStyles.primaryAccent,
                        backgroundColor: AppStyles.glassCardBorder,
                        minHeight: 4.0 * scale,
                      ),
                    ),
                    SizedBox(height: 16.0 * scale),
                    Text(
                      "Đang kiểm tra các thông số kỹ thuật...",
                      style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale),
                    ),
                    SizedBox(height: 19.0 * scale),
                  ],

                  if (vm.startupCheckLogs.isNotEmpty) ...[
                    Container(
                      constraints: BoxConstraints(maxWidth: 800.0 * scale),
                      padding: EdgeInsets.fromLTRB(16.0 * scale, 0.0, 16.0 * scale, 16.0 * scale),
                      margin: EdgeInsets.symmetric(horizontal: 24.0 * scale),
                      decoration: AppStyles.glassDecoration(
                        borderColor: vm.errorMessage.isNotEmpty 
                            ? AppStyles.errorColor.withValues(alpha: 0.3) 
                            : AppStyles.glassCardBorder,
                        radius: 16.0 * scale,
                      ),
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12.0 * scale,
                        mainAxisSpacing: 12.0 * scale,
                        childAspectRatio: 4.8,
                        children: vm.startupCheckLogs.map((log) {
                              final isPass = log.contains("PASS");
                              return Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.0 * scale, vertical: 6.0 * scale),
                                decoration: BoxDecoration(
                                  color: isPass 
                                      ? AppStyles.successColor.withValues(alpha: 0.05) 
                                      : AppStyles.errorColor.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6.0 * scale),
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
                                      size: 16.0 * scale,
                                    ),
                                    SizedBox(width: 8.0 * scale),
                                    Expanded(
                                      child: Text(
                                        log,
                                        style: TextStyle(
                                          color: isPass ? AppStyles.textPrimary : AppStyles.errorColor,
                                          fontFamily: 'monospace',
                                          fontSize: 12.0 * scale,
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
                        SizedBox(height: 24.0 * scale),
                      ],

                  if (!vm.isValidating && vm.errorMessage.isNotEmpty) ...[
                    ElevatedButton.icon(
                      onPressed: () => vm.runStartupChecks(),
                      icon: Icon(Icons.refresh, size: 18.0 * scale),
                      label: Text("Thử Lại", style: TextStyle(fontSize: 14.0 * scale)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.primaryAccent,
                        foregroundColor: AppStyles.backgroundEnd,
                        padding: EdgeInsets.symmetric(horizontal: 24.0 * scale, vertical: 12.0 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
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
