import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/styles.dart';
import '../viewmodels/conversation_viewmodel.dart';
import '../viewmodels/main_viewmodel.dart';

class ConversationView extends StatefulWidget {
  const ConversationView({super.key});

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _chatInputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConversationViewModel>();
    final mainVm = context.read<MainViewModel>();

    // Auto-scroll when messages are added
    _scrollToBottom();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppStyles.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Landscape split Row
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TOP CONTROL BAR: Horizontal row of controls
                    Row(
                      children: [
                        // Current system state indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                          decoration: AppStyles.glassDecoration(radius: 8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10.0,
                                height: 10.0,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: vm.isProcessing ? AppStyles.warningColor : AppStyles.successColor,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                vm.isProcessing ? "Đang xử lý phản hồi..." : "Trợ lý hoạt động",
                                style: TextStyle(
                                  color: vm.isProcessing ? AppStyles.warningColor : AppStyles.successColor,
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12.0),
  
                        // Mute Speech button
                        ElevatedButton.icon(
                          onPressed: () => vm.toggleMute(),
                          icon: Icon(vm.isMuted ? Icons.volume_off : Icons.volume_up, size: 18.0),
                          label: Text(vm.isMuted ? "BẬT ÂM" : "TẮT ÂM"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: vm.isMuted ? AppStyles.warningColor : AppStyles.primaryAccent,
                            foregroundColor: AppStyles.backgroundEnd,
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                            elevation: 0.0,
                          ),
                        ),
                        const SizedBox(width: 12.0),
  
                        // Run Demo script button
                        ElevatedButton.icon(
                          onPressed: () => vm.runDemoModeAsync(),
                          icon: const Icon(Icons.slideshow, size: 18.0),
                          label: const Text("CHẠY KỊCH BẢN DEMO"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppStyles.glassCardBg,
                            foregroundColor: AppStyles.textPrimary,
                            surfaceTintColor: Colors.transparent,
                            side: const BorderSide(color: AppStyles.glassCardBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                            elevation: 0.0,
                          ),
                        ),
                        
                        const Spacer(),
  
                        // Stop / Finalize Button
                        ElevatedButton.icon(
                          onPressed: () => vm.showFinalizeAsync(),
                          icon: const Icon(Icons.check_circle_outline, size: 18.0),
                          label: const Text("KẾT THÚC HỘI THOẠI & PHÊ DUYỆT"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppStyles.errorColor,
                            foregroundColor: AppStyles.textPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.0),
                            elevation: 0.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16.0),

                    // FULL WIDTH: Chat dialogue bubble history stream
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: AppStyles.glassDecoration(),
                        child: Column(
                          children: [
                            const Text("HỘI THOẠI TRỰC TIẾP", style: AppStyles.bodyLarge),
                            const SizedBox(height: 12.0),
                            
                            // Scrollable list of chat bubbles
                            Expanded(
                              child: vm.messages.isEmpty
                                  ? const Center(
                                      child: Text("Bắt đầu nói chuyện...", style: AppStyles.caption),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      itemCount: vm.messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = vm.messages[index];
                                        final isPatient = msg.sender == "Người cần giúp đỡ" || msg.sender == "Patient";
                                        final isSystem = msg.sender == "System";
 
                                        if (isSystem) {
                                          return Center(
                                            child: Container(
                                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(12.0),
                                              ),
                                              child: Text(msg.content, style: AppStyles.caption),
                                            ),
                                          );
                                        }
 
                                        return Align(
                                          alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(vertical: 6.0),
                                            padding: const EdgeInsets.all(14.0),
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context).size.width * 0.55,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isPatient
                                                  ? AppStyles.secondaryAccent.withValues(alpha: 0.35)
                                                  : AppStyles.glassCardBorder.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(16.0),
                                                topRight: const Radius.circular(16.0),
                                                bottomLeft: isPatient ? const Radius.circular(16.0) : Radius.zero,
                                                bottomRight: isPatient ? Radius.zero : const Radius.circular(16.0),
                                              ),
                                              border: Border.all(
                                                color: isPatient
                                                    ? AppStyles.secondaryAccent.withValues(alpha: 0.5)
                                                    : AppStyles.glassCardBorder,
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  msg.sender,
                                                  style: AppStyles.caption.copyWith(
                                                    color: isPatient ? AppStyles.secondaryAccent : AppStyles.primaryAccent,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 6.0),
                                                Text(
                                                  msg.content,
                                                  style: AppStyles.bodyLarge.copyWith(fontWeight: FontWeight.normal),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            const SizedBox(height: 12.0),
 
                            // User text manual override input row
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: AppStyles.glassDecoration(radius: 12.0),
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: TextField(
                                      controller: _chatInputController,
                                      style: AppStyles.bodyLarge,
                                      decoration: const InputDecoration(
                                        hintText: "Nhập phản hồi của bệnh nhân...",
                                        hintStyle: AppStyles.caption,
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          vm.userInput = val;
                                          vm.sendMessageAsync();
                                          _chatInputController.clear();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12.0),
                                SizedBox(
                                  height: 50.0,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      final val = _chatInputController.text;
                                      if (val.trim().isNotEmpty) {
                                        vm.userInput = val;
                                        vm.sendMessageAsync();
                                        _chatInputController.clear();
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

              // OVERLAY DIALOG: Summary details popup
              if (vm.isSummaryVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 600.0,
                      height: 450.0,
                      padding: const EdgeInsets.all(28.0),
                      decoration: AppStyles.glassDecoration(borderColor: AppStyles.primaryAccent),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.assignment, color: AppStyles.primaryAccent, size: 28.0),
                                  SizedBox(width: 12.0),
                                  Text("TÓM TẮT THÔNG TIN HỘI THOẠI", style: AppStyles.titleLarge),
                                ],
                              ),
                              IconButton(
                                onPressed: () => vm.closeSummary(),
                                icon: const Icon(Icons.close, color: AppStyles.textSecondary),
                              )
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: AppStyles.glassCardBorder),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  vm.summaryResult,
                                  style: AppStyles.bodyMedium.copyWith(height: 1.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20.0),
                          SizedBox(
                            height: 45.0,
                            child: ElevatedButton(
                              onPressed: () => vm.closeSummary(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppStyles.primaryAccent,
                                foregroundColor: AppStyles.backgroundEnd,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              child: const Text("ĐÓNG TÓM TẮT"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // OVERLAY DIALOG: Finalize verification popup
              if (vm.isFinalizeVisible)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Container(
                      width: 600.0,
                      height: 480.0,
                      padding: const EdgeInsets.all(28.0),
                      decoration: AppStyles.glassDecoration(
                        borderColor: vm.isFinalizeConfirmed ? AppStyles.successColor : AppStyles.errorColor,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    vm.isFinalizeConfirmed ? Icons.task_alt : Icons.analytics_outlined,
                                    color: vm.isFinalizeConfirmed ? AppStyles.successColor : AppStyles.errorColor,
                                    size: 28.0,
                                  ),
                                  const SizedBox(width: 12.0),
                                  const Text("TÓM TẮT HỘI THOẠI", style: AppStyles.titleLarge),
                                ],
                              ),
                              if (!vm.isFinalizeConfirmed)
                                IconButton(
                                  onPressed: () => vm.cancelFinalize(),
                                  icon: const Icon(Icons.close, color: AppStyles.textSecondary),
                                )
                            ],
                          ),
                          const SizedBox(height: 16.0),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: AppStyles.glassCardBorder),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  vm.finalizeResult,
                                  style: AppStyles.bodyMedium.copyWith(height: 1.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24.0),

                          if (!vm.isFinalizeConfirmed) ...[
                            // Cancel or Confirm
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50.0,
                                    child: OutlinedButton(
                                      onPressed: () => vm.cancelFinalize(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppStyles.textPrimary,
                                        side: const BorderSide(color: AppStyles.glassCardBorder),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                      ),
                                      child: const Text("HỦY - TIẾP TỤC NÓI CHUYỆN"),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16.0),
                                Expanded(
                                  child: SizedBox(
                                    height: 50.0,
                                    child: ElevatedButton(
                                      onPressed: () => vm.confirmFinalize(),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppStyles.successColor,
                                        foregroundColor: AppStyles.backgroundEnd,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                      ),
                                      child: const Text("XÁC NHẬN KẾT THÚC"),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ] else ...[
                            // Go to result screen
                            SizedBox(
                              height: 50.0,
                              child: ElevatedButton(
                                onPressed: () {
                                  vm.navigateToResult(() {
                                    mainVm.navigateTo(AppStage.result);
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppStyles.primaryAccent,
                                  foregroundColor: AppStyles.backgroundEnd,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                ),
                                child: const Text("ĐI ĐẾN TRANG KẾT QUẢ", style: AppStyles.bodyLarge),
                              ),
                            ),
                          ]
                        ],
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
}
