import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/conversation_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';
import '../viewmodels/result_viewmodel.dart';
import '../viewmodels/auth_viewmodel.dart';

class ResultView extends StatefulWidget {
  const ResultView({super.key});

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  late final FocusNode _topRestartFocusNode;
  late final FocusNode _bottomRestartFocusNode;
  bool _isTopRestartFocused = false;
  bool _isBottomRestartFocused = false;
  bool _hasRequestedFocus = false;

  @override
  void initState() {
    super.initState();
    _topRestartFocusNode = FocusNode();
    _topRestartFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isTopRestartFocused = _topRestartFocusNode.hasFocus;
        });
      }
    });
    _bottomRestartFocusNode = FocusNode();
    _bottomRestartFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isBottomRestartFocused = _bottomRestartFocusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _topRestartFocusNode.dispose();
    _bottomRestartFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultVm = context.watch<ResultViewModel>();
    final mainVm = context.read<MainViewModel>();
    final authVm = context.read<AuthViewModel>();
    final converseVm = context.read<ConversationViewModel>();

    final Size screenSize = MediaQuery.of(context).size;
    double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);
    scale = 1.2; // 1.5

    // Automatically focus the top restart button when the result is calculated and ready
    if (resultVm.isResultReady && !_hasRequestedFocus) {
      _hasRequestedFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _topRestartFocusNode.requestFocus();
        }
      });
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.0 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Panel
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.assessment, color: AppStyles.primaryAccent, size: 28.0 * scale),
                        SizedBox(width: 12.0 * scale),
                        Text(
                          "KẾT QUẢ PHÂN TÍCH CA HỖ TRỢ",
                          style: AppStyles.titleLarge.copyWith(fontSize: 24.0 * scale),
                        ),
                      ],
                    ),
                    if (resultVm.isResultReady)
                      AnimatedScale(
                        scale: _isTopRestartFocused ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8.0 * scale),
                            boxShadow: _isTopRestartFocused
                                ? [
                                    BoxShadow(
                                      color: AppStyles.primaryAccent.withValues(alpha: 0.6),
                                      blurRadius: 15.0 * scale,
                                      spreadRadius: 3.0 * scale,
                                    ),
                                  ]
                                : [],
                          ),
                          child: ElevatedButton.icon(
                            focusNode: _topRestartFocusNode,
                            onPressed: () {
                              // Clear views and restart Auth cycle
                              authVm.resetVerification();
                              converseVm.clearConversation();
                              resultVm.reset();
                              mainVm.resetApp();
                            },
                            icon: Icon(Icons.refresh, size: 18.0 * scale),
                            label: Text(
                              "Khởi Động Ca Mới",
                              style: TextStyle(fontSize: 13.0 * scale, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isTopRestartFocused 
                                  ? AppStyles.primaryAccent 
                                  : AppStyles.primaryAccent.withValues(alpha: 0.7),
                              foregroundColor: AppStyles.backgroundEnd,
                              elevation: _isTopRestartFocused ? 10.0 : 0.0,
                              side: _isTopRestartFocused 
                                  ? BorderSide(color: Colors.white, width: 2.5 * scale) 
                                  : null,
                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale, vertical: 12.0 * scale),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                            ),
                          ),
                        ),
                      )
                  ],
                ),
                SizedBox(height: 20.0 * scale),
 
                // Main landscape split view
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // LEFT COLUMN: Distress Scoring AI detail
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(20.0 * scale, 10.0 * scale, 20.0 * scale, 20.0 * scale),
                          decoration: AppStyles.glassDecoration(radius: 16.0 * scale),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "BÁO CÁO PHÂN TÍCH DISTRESS SCORE AI",
                                style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                              ),
                              SizedBox(height: 8.0 * scale),
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.all(16.0 * scale),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(12.0 * scale),
                                    border: Border.all(color: AppStyles.glassCardBorder),
                                  ),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      resultVm.distressScore,
                                      style: AppStyles.bodyMedium.copyWith(
                                        fontSize: 14.0 * scale,
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
                      SizedBox(width: 24.0 * scale),
 
                      // RIGHT COLUMN: Money approved and decision
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: EdgeInsets.all(20.0 * scale),
                          decoration: AppStyles.glassDecoration(
                            borderColor: resultVm.isResultReady ? AppStyles.successColor.withValues(alpha: 0.3) : null,
                            radius: 16.0 * scale,
                          ),
                          child: !resultVm.isResultReady
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(color: AppStyles.primaryAccent, strokeWidth: 4.0 * scale),
                                      SizedBox(height: 16.0 * scale),
                                      Text(
                                        "Đang tính điểm và duyệt hạn mức...",
                                        style: AppStyles.bodyMedium.copyWith(fontSize: 14.0 * scale),
                                      ),
                                    ],
                                  ),
                                )
                              : Stack(
                                  children: [
                                    // Top-left Distress Score Info
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 10.0 * scale, vertical: 6.0 * scale),
                                        decoration: BoxDecoration(
                                          color: AppStyles.primaryAccent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6.0 * scale),
                                          border: Border.all(color: AppStyles.primaryAccent.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          "Distress Score: ${resultVm.score.toStringAsFixed(0)}%",
                                          style: TextStyle(
                                            color: AppStyles.primaryAccent,
                                            fontSize: 12.0 * scale,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ),
                                    
                                    // Main content
                                    Positioned.fill(
                                      child: SingleChildScrollView(
                                        physics: const BouncingScrollPhysics(),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            SizedBox(height: 40.0 * scale), // Spacer for top-left distress badge
                                            Icon(Icons.verified, color: AppStyles.successColor, size: 56.0 * scale),
                                            SizedBox(height: 6.0 * scale),
                                            Text(
                                              "SỐ TIỀN PHÊ DUYỆT CHỈ ĐỊNH",
                                              style: AppStyles.bodyLarge.copyWith(fontSize: 16.0 * scale),
                                            ),
                                            SizedBox(height: 16.0 * scale),
   
                                            // Big Glowing Approved Amount Box
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 24.0 * scale, vertical: 16.0 * scale),
                                              decoration: BoxDecoration(
                                                color: AppStyles.successColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(16.0 * scale),
                                                border: Border.all(color: AppStyles.successColor, width: 1.5 * scale),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppStyles.successColor.withValues(alpha: 0.2),
                                                    blurRadius: 16.0 * scale,
                                                    spreadRadius: 2.0 * scale,
                                                  )
                                                ],
                                              ),
                                              child: Text(
                                                "${_formatCurrency(resultVm.decision?.approvedAmount ?? 0.0)} VNĐ",
                                                style: AppStyles.titleHuge.copyWith(
                                                  color: AppStyles.successColor,
                                                  fontSize: 36.0 * scale,
                                                ),
                                              ),
                                            ),
                                            SizedBox(height: 24.0 * scale),
   
                                            // Decision explanation details
                                            Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 16.0 * scale),
                                              child: Text(
                                                resultVm.decision?.explanation ?? "",
                                                style: AppStyles.bodyMedium.copyWith(
                                                  color: AppStyles.textSecondary,
                                                  fontSize: 14.0 * scale,
                                                  height: 1.5,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            SizedBox(height: 24.0 * scale),
   
                                            // Restart button at bottom
                                            AnimatedScale(
                                              scale: _isBottomRestartFocused ? 1.05 : 1.0,
                                              duration: const Duration(milliseconds: 200),
                                              curve: Curves.easeInOut,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200),
                                                curve: Curves.easeInOut,
                                                width: double.infinity,
                                                height: 55.0 * scale,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(12.0 * scale),
                                                  boxShadow: _isBottomRestartFocused
                                                      ? [
                                                          BoxShadow(
                                                            color: AppStyles.successColor.withValues(alpha: 0.6),
                                                            blurRadius: 20.0 * scale,
                                                            spreadRadius: 4.0 * scale,
                                                          ),
                                                        ]
                                                      : [],
                                                ),
                                                child: ElevatedButton(
                                                  focusNode: _bottomRestartFocusNode,
                                                  onPressed: () {
                                                    authVm.resetVerification();
                                                    converseVm.clearConversation();
                                                    resultVm.reset();
                                                    mainVm.resetApp();
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: _isBottomRestartFocused 
                                                        ? AppStyles.successColor 
                                                        : AppStyles.successColor.withValues(alpha: 0.7),
                                                    foregroundColor: AppStyles.backgroundEnd,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0 * scale)),
                                                    side: _isBottomRestartFocused 
                                                        ? BorderSide(color: Colors.white, width: 3.5 * scale) 
                                                        : null,
                                                    elevation: _isBottomRestartFocused ? 15.0 : 0.0,
                                                  ),
                                                  child: Text(
                                                    "HOÀN TẤT VÀ KHỞI ĐỘNG LẠI CA MỚI",
                                                    style: AppStyles.bodyLarge.copyWith(
                                                      fontSize: 16.0 * scale,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
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
