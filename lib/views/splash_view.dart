import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/main_viewmodel.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  late final FocusNode _retryFocusNode;
  bool _isRetryFocused = false;
  bool _hasRequestedFocus = false;

  @override
  void initState() {
    super.initState();
    _retryFocusNode = FocusNode();
    _retryFocusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isRetryFocused = _retryFocusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _retryFocusNode.dispose();
    super.dispose();
  }

  Widget _buildLogItem(String log, double scale) {
    final parts = log.split(" - ");
    final String id = parts.isNotEmpty ? parts[0] : log;
    final bool isPass = log.contains("PASS");
    final bool isFail = log.contains("fail");
    
    String displayMessage = "";
    if (isFail) {
      if (parts.length > 2) {
        displayMessage = parts.sublist(2).join(" - ");
      } else if (parts.length > 1) {
        displayMessage = parts[1];
      }
    } else if (!isPass) {
      // Progress message
      if (parts.length > 1) {
        displayMessage = parts.sublist(1).join(" - ");
      }
    }

    final Color borderColor = isPass 
        ? AppStyles.successColor.withValues(alpha: 0.2)
        : isFail
            ? AppStyles.errorColor.withValues(alpha: 0.2)
            : AppStyles.primaryAccent.withValues(alpha: 0.2);

    final Color bgColor = isPass 
        ? AppStyles.successColor.withValues(alpha: 0.05)
        : isFail
            ? AppStyles.errorColor.withValues(alpha: 0.05)
            : AppStyles.primaryAccent.withValues(alpha: 0.05);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.0 * scale, vertical: 6.0 * scale),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6.0 * scale),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2.0 * scale),
            child: isPass
                ? Icon(
                    Icons.check_circle_outline,
                    color: AppStyles.successColor,
                    size: 16.0 * scale,
                  )
                : isFail
                    ? Icon(
                        Icons.error_outline,
                        color: AppStyles.errorColor,
                        size: 16.0 * scale,
                      )
                    : SizedBox(
                        width: 12.0 * scale,
                        height: 12.0 * scale,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: AppStyles.primaryAccent,
                        ),
                      ),
          ),
          SizedBox(width: 8.0 * scale),
          Expanded(
            child: isPass
                ? Text(
                    id,
                    style: TextStyle(
                      color: AppStyles.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 12.0 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.0 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: "$id: ",
                          style: TextStyle(
                            color: isFail ? AppStyles.errorColor : AppStyles.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: displayMessage,
                          style: TextStyle(
                            color: isFail ? AppStyles.errorColor : AppStyles.textSecondary,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MainViewModel>();
    final Size screenSize = MediaQuery.of(context).size;
    double scale = (screenSize.height / 720.0 * MediaQuery.of(context).devicePixelRatio).clamp(1.0, 2.5);
    scale = 1.9; // 1.9 - 1.4

    // Request focus on the retry button if validation failed and we haven't requested it yet
    if (!vm.isValidating && vm.errorMessage.isNotEmpty && !_hasRequestedFocus) {
      _hasRequestedFocus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _retryFocusNode.requestFocus();
        }
      });
    } else if (vm.isValidating) {
      _hasRequestedFocus = false;
    }

    final List<List<String>> chunkedLogs = [];
    for (var i = 0; i < vm.startupCheckLogs.length; i += 5) {
      chunkedLogs.add(
        vm.startupCheckLogs.sublist(
          i,
          i + 5 > vm.startupCheckLogs.length ? vm.startupCheckLogs.length : i + 5,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppStyles.backgroundEnd,
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
                      padding: EdgeInsets.all(16.0 * scale),
                      margin: EdgeInsets.symmetric(horizontal: 24.0 * scale),
                      decoration: AppStyles.glassDecoration(
                        borderColor: vm.errorMessage.isNotEmpty 
                            ? AppStyles.errorColor.withValues(alpha: 0.3) 
                            : AppStyles.glassCardBorder,
                        radius: 16.0 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var rowIndex = 0; rowIndex < chunkedLogs.length; rowIndex++) ...[
                            if (rowIndex > 0) SizedBox(height: 12.0 * scale),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var colIndex = 0; colIndex < 5; colIndex++)
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: colIndex < 4 ? 12.0 * scale : 0,
                                      ),
                                      child: colIndex < chunkedLogs[rowIndex].length
                                          ? _buildLogItem(chunkedLogs[rowIndex][colIndex], scale)
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 24.0 * scale),
                  ],

                  if (!vm.isValidating && vm.errorMessage.isNotEmpty) ...[
                    AnimatedScale(
                      scale: _isRetryFocused ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8.0 * scale),
                          boxShadow: _isRetryFocused
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
                          focusNode: _retryFocusNode,
                          onPressed: () => vm.runStartupChecks(),
                          icon: Icon(Icons.refresh, size: 18.0 * scale),
                          label: Text(
                            "Thử Lại",
                            style: TextStyle(
                              fontSize: 14.0 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRetryFocused 
                                ? AppStyles.primaryAccent 
                                : AppStyles.primaryAccent.withValues(alpha: 0.7),
                            foregroundColor: AppStyles.backgroundEnd,
                            elevation: _isRetryFocused ? 12.0 : 0.0,
                            side: _isRetryFocused 
                                ? BorderSide(color: Colors.white, width: 2.5 * scale) 
                                : null,
                            padding: EdgeInsets.symmetric(horizontal: 24.0 * scale, vertical: 12.0 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0 * scale)),
                          ),
                        ),
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
