import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/main_viewmodel.dart';
import 'auth_view.dart';
import 'conversation_view.dart';
import 'result_view.dart';
import 'splash_view.dart';

class MainView extends StatelessWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context) {
    final mainVm = context.watch<MainViewModel>();

    switch (mainVm.currentStage) {
      case AppStage.splash:
        return const SplashView();
      case AppStage.auth:
        return const AuthView();
      case AppStage.conversation:
        return const ConversationView();
      case AppStage.result:
        return const ResultView();
    }
  }
}
