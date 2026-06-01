import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/conversation_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';
import '../viewmodels/result_viewmodel.dart';
import '../viewmodels/auth_viewmodel.dart';

class ResultView extends StatelessWidget {
  const ResultView({super.key});

  @override
  Widget build(BuildContext context) {
    final resultVm = context.watch<ResultViewModel>();
    final mainVm = context.read<MainViewModel>();
    final authVm = context.read<AuthViewModel>();
    final converseVm = context.read<ConversationViewModel>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Panel
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.assessment, color: AppStyles.primaryAccent, size: 28.0),
                        SizedBox(width: 12.0),
                        Text("KẾT QUẢ PHÂN TÍCH CA HỖ TRỢ", style: AppStyles.titleLarge),
                      ],
                    ),
                    if (resultVm.isResultReady)
                      ElevatedButton.icon(
                        onPressed: () {
                          // Clear views and restart Auth cycle
                          authVm.resetVerification();
                          converseVm.clearConversation();
                          resultVm.reset();
                          mainVm.resetApp();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text("Khởi Động Ca Mới"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppStyles.primaryAccent,
                          foregroundColor: AppStyles.backgroundEnd,
                          elevation: 0.0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        ),
                      )
                  ],
                ),
                const SizedBox(height: 20.0),

                // Main landscape split view
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // LEFT COLUMN: Distress Scoring AI detail
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(20.0),
                          decoration: AppStyles.glassDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("BÁO CÁO PHÂN TÍCH DISTRESS SCORE AI", style: AppStyles.bodyLarge),
                              const SizedBox(height: 12.0),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16.0),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(12.0),
                                    border: Border.all(color: AppStyles.glassCardBorder),
                                  ),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      resultVm.distressScore,
                                      style: AppStyles.bodyMedium.copyWith(
                                        height: 1.6,
                                        color: AppStyles.textPrimary,
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

                      // RIGHT COLUMN: Money approved and decision
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(20.0),
                          decoration: AppStyles.glassDecoration(
                            borderColor: resultVm.isResultReady ? AppStyles.successColor.withValues(alpha: 0.3) : null,
                          ),
                          child: !resultVm.isResultReady
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: AppStyles.primaryAccent),
                                      SizedBox(height: 16.0),
                                      Text("Đang tính điểm và duyệt hạn mức...", style: AppStyles.bodyMedium),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const SizedBox(height: 12.0),
                                      const Icon(Icons.verified, color: AppStyles.successColor, size: 56.0),
                                      const SizedBox(height: 12.0),
                                      const Text(
                                        "SỐ TIỀN PHÊ DUYỆT CHỈ ĐỊNH",
                                        style: AppStyles.bodyLarge,
                                      ),
                                      const SizedBox(height: 16.0),
  
                                      // Big Glowing Approved Amount Box
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                                        decoration: BoxDecoration(
                                          color: AppStyles.successColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(16.0),
                                          border: Border.all(color: AppStyles.successColor, width: 1.5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppStyles.successColor.withValues(alpha: 0.2),
                                              blurRadius: 16.0,
                                              spreadRadius: 2.0,
                                            )
                                          ],
                                        ),
                                        child: Text(
                                          "${_formatCurrency(resultVm.decision?.approvedAmount ?? 0.0)} VNĐ",
                                          style: AppStyles.titleHuge.copyWith(
                                            color: AppStyles.successColor,
                                            fontSize: 36.0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24.0),
  
                                      // Decision explanation details
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        child: Text(
                                          resultVm.decision?.explanation ?? "",
                                          style: AppStyles.bodyMedium.copyWith(
                                            color: AppStyles.textSecondary,
                                            height: 1.5,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      const SizedBox(height: 24.0),
  
                                      // Restart button at bottom
                                      SizedBox(
                                        width: double.infinity,
                                        height: 55.0,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            authVm.resetVerification();
                                            converseVm.clearConversation();
                                            resultVm.reset();
                                            mainVm.resetApp();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppStyles.successColor,
                                            foregroundColor: AppStyles.backgroundEnd,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                                            elevation: 0.0,
                                          ),
                                          child: const Text("HOÀN TẤT VÀ KHỞI ĐỘNG LẠI CA MỚI", style: AppStyles.bodyLarge),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
