import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/data_service.dart';
import 'services/auth_service.dart';
import 'services/camera_service.dart';
import 'services/ocr_service.dart';
import 'services/qr_service.dart';
import 'services/llm_service.dart';
import 'services/rule_engine_service.dart';
import 'services/speech_service.dart';
import 'services/speech_manager.dart';
import 'services/log_service.dart';
import 'viewmodels/main_viewmodel.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/conversation_viewmodel.dart';
import 'viewmodels/result_viewmodel.dart';
import 'views/main_view.dart';
import 'views/log_console_overlay.dart';
import 'views/robot_face_overlay.dart';

void main() async {
  // Initialize custom logs capturing
  LogService.initialize();

  // Ensure native bindings are fully up
  WidgetsFlutterBinding.ensureInitialized();

  // Force Landscape Orientation for premium table/tablet layout experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Create singletons of core services
  final dataService = DataService();
  final cameraService = CameraService();
  final ocrService = OCRService();
  final qrService = QRService();
  final speechService = SpeechManager();
  final authService = AuthService(dataService);
  final llmService = LLMService();
  final ruleEngineService = RuleEngineService(
    llmService,
    speechService,
    cameraService,
    dataService,
    authService,
  );

  runApp(
    MultiProvider(
      providers: [
        // Services Registration
        Provider<IDataService>.value(value: dataService),
        Provider<ICameraService>.value(value: cameraService),
        Provider<IOCRService>.value(value: ocrService),
        Provider<IQRService>.value(value: qrService),
        Provider<ISpeechService>.value(value: speechService),
        Provider<IAuthService>.value(value: authService),
        Provider<ILLMService>.value(value: llmService),
        Provider<IRuleEngineService>.value(value: ruleEngineService),

        // ViewModels Registration
        ChangeNotifierProvider<MainViewModel>(
          create: (_) => MainViewModel(ruleEngineService, cameraService, dataService, llmService),
        ),
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel(
            cameraService,
            ocrService,
            qrService,
            authService,
            ruleEngineService,
            dataService,
            llmService,
            speechService,
          ),
        ),
        ChangeNotifierProvider<ConversationViewModel>(
          create: (_) => ConversationViewModel(llmService, speechService, ruleEngineService),
        ),
        ChangeNotifierProvider<ResultViewModel>(
          create: (_) => ResultViewModel(ruleEngineService, llmService),
        ),
      ],
      child: const ListeningStationApp(),
    ),
  );
}

class ListeningStationApp extends StatelessWidget {
  const ListeningStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Listening Station',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF38BDF8),
        scaffoldBackgroundColor: const Color(0xFF020617),
        fontFamily: 'Roboto', // Modern standard clean typeface
      ),
      builder: (context, child) {
        return LogConsoleOverlay(
          child: RobotFaceOverlay(child: child ?? const SizedBox()),
        );
      },
      home: const MainView(),
    );
  }
}
