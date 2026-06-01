import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

abstract class ILLMService {
  Future<void> initializeAsync();
  Future<bool> pingAsync();
  Future<String> getResponseAsync(List<ConversationMessage> history, String userPrompt);
  Future<String> getSummaryAsync(List<ConversationMessage> history);
  Future<String> getSummaryAIAsync(List<ConversationMessage> history);
  Future<List<ConversationMessage>> getDemoMessagesAsync();
  Future<String> getFinalizeAIAsync(List<ConversationMessage> history);
  Future<String> getDistressScoreAIAsync(List<ConversationMessage> history);

  List<ConversationMessage> get lastConversationHistory;
  set lastConversationHistory(List<ConversationMessage> value);

  double get proposedAmount;
  set proposedAmount(double value);

  double get caseOperatorMin;
  set caseOperatorMin(double value);

  double get caseOperatorMax;
  set caseOperatorMax(double value);

  double get caseOperatorExact;
  set caseOperatorExact(double value);

  bool get flagOperatorExact;
  set flagOperatorExact(bool value);

  String get finalizeConfirmMessage;
  String get systemPrompt;
  set systemPrompt(String value);
}

class LLMService implements ILLMService {
  final http.Client _httpClient;
  final String _baseUrl = "https://api.openai.com/v1/chat/completions";

  String? _apiKey;
  String _finalizePrompt = "";
  String _conversationPrompt = "You are a helpful assistant. Conduct a friendly interview.";
  // ignore: unused_field
  String _mannerOfSpeechPrompt = "Speak gently and kindly.";
  // ignore: unused_field
  String _conversationFormat = "";
  String _finalizeConfirmMessage = "";
  String _distressScoringPrompt = "";

  List<ConversationMessage> _lastConversationHistory = [];
  double _proposedAmount = 0.0;
  double _caseOperatorMin = 0.0;
  double _caseOperatorMax = 0.0;
  double _caseOperatorExact = 2000000.0;
  bool _flagOperatorExact = true;

  late String _dataDir;

  LLMService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  @override
  List<ConversationMessage> get lastConversationHistory => _lastConversationHistory;

  @override
  set lastConversationHistory(List<ConversationMessage> value) => _lastConversationHistory = value;

  @override
  double get proposedAmount => _proposedAmount;

  @override
  set proposedAmount(double value) => _proposedAmount = value;

  @override
  double get caseOperatorMin => _caseOperatorMin;

  @override
  set caseOperatorMin(double value) => _caseOperatorMin = value;

  @override
  double get caseOperatorMax => _caseOperatorMax;

  @override
  set caseOperatorMax(double value) => _caseOperatorMax = value;

  @override
  double get caseOperatorExact => _caseOperatorExact;

  @override
  set caseOperatorExact(double value) => _caseOperatorExact = value;

  @override
  bool get flagOperatorExact => _flagOperatorExact;

  @override
  set flagOperatorExact(bool value) => _flagOperatorExact = value;

  @override
  String get finalizeConfirmMessage => _finalizeConfirmMessage;

  @override
  String get systemPrompt => _conversationPrompt;

  @override
  set systemPrompt(String value) => _conversationPrompt = value;

  @override
  Future<void> initializeAsync() async {
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = join(appDir.path, 'ListeningStation');
    final dir = Directory(_dataDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Sync all JSON configs from soncamedia remote server
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/openAI_key.json", "openAI_key.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_conversation.json", "llm_conversation.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_manner_of_speech.json", "llm_manner_of_speech.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_conversation_demo.json", "llm_conversation_demo.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_conversation_result.json", "llm_conversation_result.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_conversation_result_confirm.json", "llm_conversation_result_confirm.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/llm_distress_scoring.json", "llm_distress_scoring.json");
    await _syncFileAsync("http://data.soncamedia.com/firmware/smartbox/listeningStation/rule_engine.json", "rule_engine.json");

    _loadConfig();
  }

  Future<void> _syncFileAsync(String remoteUrl, String localFileName) async {
    final localPath = join(_dataDir, localFileName);
    final localFile = File(localPath);
    debugPrint("\n[LLMService] Syncing: $localFileName to $localPath");
    try {
      final headResponse = await _httpClient.head(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 5));
      int remoteSize = -1;
      if (headResponse.statusCode == 200) {
        remoteSize = int.tryParse(headResponse.headers['content-length'] ?? '') ?? -1;
      }

      bool shouldDownload = true;
      if (await localFile.exists()) {
        final localSize = await localFile.length();
        if (remoteSize != -1 && remoteSize == localSize) {
          shouldDownload = false;
          debugPrint("[LLMService] $localFileName is up-to-date (size: $localSize). Skipping download.");
        }
      }

      if (shouldDownload) {
        debugPrint("[LLMService] Downloading $localFileName from $remoteUrl...");
        final getResponse = await _httpClient.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 10));
        if (getResponse.statusCode == 200) {
          await localFile.writeAsBytes(getResponse.bodyBytes);
          debugPrint("[LLMService] Synced and saved file successfully: $localFileName");
        } else {
          debugPrint("[LLMService] Failed to download $localFileName. HTTP status: ${getResponse.statusCode}");
        }
      }
    } catch (ex) {
      debugPrint("[LLMService] Error syncing LLM config file $localFileName: $ex");
    }
  }

  void _loadConfig() {
    try {
      File getSafeFile(String fileName) {
        return File(join(_dataDir, fileName));
      }

      // 1. Load API Key
      final keyFile = getSafeFile("openAI_key.json");
      debugPrint("[LLMService] Loading API key from path: ${keyFile.path}");
      if (keyFile.existsSync()) {
        final jsonStr = keyFile.readAsStringSync();
        debugPrint("[LLMService] openAI_key.json content length: ${jsonStr.length} bytes");
        final doc = jsonDecode(jsonStr);
        if (doc is Map && doc.containsKey('OpenAI')) {
          _apiKey = doc['OpenAI']['ApiKey']?.toString();
          if (_apiKey != null && _apiKey!.isNotEmpty) {
            //debugPrint("[LLMService] API Key loaded successfully. Prefix: ${_apiKey!.substring(0, min(10, _apiKey!.length))}...");
          } else {
            debugPrint("[LLMService] Warning: API Key value is empty in JSON");
          }
        } else {
          debugPrint("[LLMService] Warning: JSON does not contain 'OpenAI' map key");
        }
      } else {
        debugPrint("[LLMService] Warning: openAI_key.json does not exist locally");
      }

      // 2. Load Conversation Prompt
      final convFile = getSafeFile("llm_conversation.json");
      if (convFile.existsSync()) {
        _conversationPrompt = convFile.readAsStringSync();
      }

      // 3. Load Manner of Speech
      final mannerFile = getSafeFile("llm_manner_of_speech.json");
      if (mannerFile.existsSync()) {
        _mannerOfSpeechPrompt = mannerFile.readAsStringSync();
      }

      // 4. Load other configuration JSON texts
      final demoFile = getSafeFile("llm_conversation_demo.json");
      if (demoFile.existsSync()) _conversationFormat = demoFile.readAsStringSync();

      final resultFile = getSafeFile("llm_conversation_result.json");
      if (resultFile.existsSync()) _finalizePrompt = resultFile.readAsStringSync();

      final confirmFile = getSafeFile("llm_conversation_result_confirm.json");
      if (confirmFile.existsSync()) _finalizeConfirmMessage = confirmFile.readAsStringSync();

      final distressFile = getSafeFile("llm_distress_scoring.json");
      if (distressFile.existsSync()) _distressScoringPrompt = distressFile.readAsStringSync();
    } catch (ex) {
      debugPrint("Error loading LLM config files: \$ex");
    }
  }

  @override
  Future<bool> pingAsync() async {
    //debugPrint("[LLMService] pingAsync triggered. Current apiKey length: ${_apiKey?.length ?? 0} characters.");
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint("[LLMService] pingAsync failed: apiKey is null or empty");
      return false;
    }
    
    //debugPrint("[LLMService] pingAsync using full apiKey: $_apiKey");

    try {
      final requestBody = {
        "model": "gpt-4o",
        "messages": [
          {"role": "user", "content": "hi"}
        ],
        "max_tokens": 5
      };

      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 5));

      //debugPrint("[LLMService] pingAsync Response status code: ${response.statusCode}");
      if (response.statusCode != 200) {
        debugPrint("[LLMService] pingAsync Response body: ${response.body}");
      }
      return response.statusCode == 200;
    } catch (ex) {
      debugPrint("[LLMService] pingAsync connection error exception: $ex");
      return false;
    }
  }

  @override
  Future<String> getResponseAsync(List<ConversationMessage> history, String userPrompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return "Lỗi: Chưa cấu hình OpenAI API Key.";
    }

    try {
      final messages = [
        {
          "role": "system",
          "content": "[CONVERSATION RULES]\n$_conversationPrompt\n\n[MANNER OF SPEECH]\n$_mannerOfSpeechPrompt"
        }
      ];

      for (var msg in history) {
        messages.add({
          "role": msg.sender == "Người cần giúp đỡ" || msg.sender == "Patient" ? "user" : "assistant",
          "content": msg.content
        });
      }

      final requestBody = {
        "model": "gpt-4o",
        "messages": messages,
      };

      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        return "Lỗi API: ${response.statusCode}";
      }

      final doc = jsonDecode(response.body);
      final reply = doc['choices'][0]['message']['content']?.toString();
      return reply ?? "Không có phản hồi.";
    } catch (ex) {
      return "Lỗi kết nối: \$ex";
    }
  }

  @override
  Future<String> getSummaryAsync(List<ConversationMessage> history) async {
    try {
      final jsonFile = File(join(_dataDir, "llm_conversation_demo.json"));
      if (!jsonFile.existsSync()) return "Lỗi: Không tìm thấy tệp định dạng tóm tắt.";

      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> rootMap = jsonDecode(jsonContent);

      final List<QuestionItem> allQuestions = [];
      final List<PhaseItem> phases = [];

      rootMap.forEach((key, val) {
        final phase = PhaseItem.fromJson(val);
        phases.add(phase);
        allQuestions.addAll(phase.questions);
      });

      int lastMatchIdx = -1;

      for (int i = 0; i < history.length - 1; i++) {
        var aiMsg = history[i];
        if (aiMsg.sender != "Trạm Lắng Nghe") continue;

        QuestionItem? bestMatch;
        double bestScore = 0.0;
        int bestMatchIdx = -1;

        for (int j = lastMatchIdx + 1; j < allQuestions.length; j++) {
          final q = allQuestions[j];
          double score = _calculateSimilarity(aiMsg.content, q.question);

          if (score > bestScore) {
            bestScore = score;
            bestMatch = q;
            bestMatchIdx = j;
          }

          if (score >= 0.9) break;
        }

        if (bestMatch != null && bestScore >= 0.5) {
          var userMsg = history[i + 1];
          if (userMsg.sender == "Người cần giúp đỡ" || userMsg.sender == "Patient") {
            bestMatch.answer = userMsg.content;
            lastMatchIdx = bestMatchIdx;
            i++; // Skip the user response in next iteration
          }
        }
      }

      final sb = StringBuffer();
      sb.writeln("=== TÓM TẮT THÔNG TIN HỘI THOẠI ===");
      sb.writeln();

      for (var phase in phases) {
        final answeredQuestions = phase.questions.where((q) => q.answer.trim().isNotEmpty).toList();
        if (answeredQuestions.isNotEmpty) {
          sb.writeln("[ \${phase.phaseName.toUpperCase()} ]");
          // ignore: unused_local_variable
          for (var q in answeredQuestions) {
            sb.writeln("- ${q.titleQuestion}: ${q.answer}");
          }
          sb.writeln();
        }
      }

      if (sb.length < 50) return "Chưa thu thập đủ thông tin để tóm tắt.";
      return sb.toString();
    } catch (ex) {
      return "Lỗi xử lý tóm tắt: \$ex";
    }
  }

  double _calculateSimilarity(String content, String template) {
    if (content.trim().isEmpty || template.trim().isEmpty) return 0.0;

    final contentLower = content.toLowerCase();
    final templateLower = template.toLowerCase();

    if (contentLower.contains(templateLower) || templateLower.contains(contentLower)) return 0.9;

    final wordRegex = RegExp(r'[ \?\,\.\!\:\;]');
    final contentWords = contentLower.split(wordRegex).where((w) => w.length > 3).toSet();
    final templateWords = templateLower.split(wordRegex).where((w) => w.length > 3).toSet();

    if (templateWords.isEmpty) return 0.0;

    int matches = templateWords.where((w) => contentWords.contains(w)).length;
    return matches / templateWords.length;
  }

  @override
  Future<String> getSummaryAIAsync(List<ConversationMessage> history) async {
    if (_apiKey == null || _apiKey!.isEmpty) return "Lỗi: Chưa cấu hình OpenAI API Key.";

    try {
      final sbTranscript = StringBuffer();
      sbTranscript.writeln("--- BẮT ĐẦU BẢN GHI HỘI THOẠI ---");
      for (var msg in history) {
        sbTranscript.writeln("${msg.sender}: ${msg.content}");
      }
      sbTranscript.writeln("--- KẾT THÚC BẢN GHI HỘI THOẠI ---");

      final messages = [
        {
          "role": "system",
          "content": "BẠN LÀ MỘT CHUYÊN VIÊN PHÂN TÍCH VÀ TỔNG HỢP HỒ SƠ. Nhiệm vụ của bạn là đọc bản ghi hội thoại (transcript) được cung cấp và lập một bản báo cáo tóm tắt các thông tin quan trọng. \n\n"
              "QUY TẮC QUAN TRỌNG:\n"
              "1. TUYỆT ĐỐI KHÔNG TIẾP TỤC HỘI THOẠI.\n"
              "2. KHÔNG ĐƯỢC ĐẶT BẤT KỲ CÂU HỎI NÀO.\n"
              "3. KHÔNG XƯNG 'CON', 'EM' HAY 'TRẠM LẮNG NGHE'. Hãy dùng ngôi thứ ba khách quan.\n"
              "4. Nếu thông tin nào chưa có trong hội thoại, hãy ghi 'Chưa có thông tin'.\n"
              "5. Chỉ trả về bản tóm tắt, không thêm lời dẫn hay kết bài."
        },
        {"role": "user", "content": "Hãy tóm tắt bản ghi sau đây:\n\n$sbTranscript"}
      ];

      final requestBody = {
        "model": "gpt-4o",
        "messages": messages,
      };

      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) return "Lỗi API: ${response.statusCode}";

      final doc = jsonDecode(response.body);
      final reply = doc['choices'][0]['message']['content']?.toString();
      return reply ?? "Không thể tạo bản tóm tắt.";
    } catch (ex) {
      return "Lỗi: $ex";
    }
  }

  @override
  Future<List<ConversationMessage>> getDemoMessagesAsync() async {
    final demoMessages = <ConversationMessage>[];
    try {
      final jsonFile = File(join(_dataDir, "llm_conversation_demo.json"));
      if (!jsonFile.existsSync()) return demoMessages;

      final jsonContent = await jsonFile.readAsString();
      final Map<String, dynamic> rootMap = jsonDecode(jsonContent);

      rootMap.forEach((key, val) {
        final phase = PhaseItem.fromJson(val);
        for (var q in phase.questions) {
          if (q.question.trim().isNotEmpty) {
            demoMessages.add(ConversationMessage(
              sender: "Trạm Lắng Nghe",
              content: q.question,
              timestamp: DateTime.now(),
            ));

            String answer = q.answer.trim().isNotEmpty ? q.answer : "[Dữ liệu Demo]";
            demoMessages.add(ConversationMessage(
              sender: "Người cần giúp đỡ",
              content: answer,
              timestamp: DateTime.now(),
            ));
          }
        }
      });
    } catch (ex) {
      debugPrint("Error creating demo messages: \$ex");
    }
    return demoMessages;
  }

  @override
  Future<String> getFinalizeAIAsync(List<ConversationMessage> history) async {
    if (_apiKey == null || _apiKey!.isEmpty) return "Lỗi: Chưa cấu hình OpenAI API Key.";

    try {
      final messages = [
        {"role": "system", "content": _finalizePrompt}
      ];

      for (var msg in history) {
        messages.add({
          "role": msg.sender == "Người cần giúp đỡ" || msg.sender == "Patient" ? "user" : "assistant",
          "content": msg.content
        });
      }

      // Add the explicit finalize command
      messages.add({"role": "user", "content": "Kiểm tra thông tin"});

      final requestBody = {
        "model": "gpt-4o",
        "messages": messages,
      };

      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) return "Lỗi API: ${response.statusCode}";

      final doc = jsonDecode(response.body);
      final reply = doc['choices'][0]['message']['content']?.toString();
      return reply ?? "Không thể xác nhận kết thúc.";
    } catch (ex) {
      return "Lỗi: $ex";
    }
  }

  @override
  Future<String> getDistressScoreAIAsync(List<ConversationMessage> history) async {
    if (_apiKey == null || _apiKey!.isEmpty) return "Lỗi: Chưa cấu hình OpenAI API Key.";
    if (_distressScoringPrompt.isEmpty) return "Lỗi: Không tìm thấy tệp định dạng tính điểm.";

    try {
      final messages = [
        {"role": "system", "content": _distressScoringPrompt}
      ];

      final conversationText = history.map((m) => "${m.sender}: ${m.content}").join("\n");
      messages.add({"role": "user", "content": "Tính tổng điểm cho trường hợp sau:\n$conversationText"});

      final requestBody = {
        "model": "gpt-4o",
        "messages": messages,
      };

      final response = await _httpClient.post(
        Uri.parse(_baseUrl),
        headers: {
          "Authorization": "Bearer $_apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) return "Lỗi API: ${response.statusCode}";

      final doc = jsonDecode(response.body);
      final reply = doc['choices'][0]['message']['content']?.toString();
      return reply ?? "Không thể tính điểm.";
    } catch (ex) {
      return "Lỗi: $ex";
    }
  }
}

class QuestionItem {
  final String titleQuestion;
  final String question;
  String answer;

  QuestionItem({
    required this.titleQuestion,
    required this.question,
    this.answer = "",
  });

  factory QuestionItem.fromJson(Map<String, dynamic> json) {
    return QuestionItem(
      titleQuestion: json['titleQuestion']?.toString() ?? json['title_question']?.toString() ?? "",
      question: json['Question']?.toString() ?? json['question']?.toString() ?? "",
      answer: json['Answer']?.toString() ?? json['answer']?.toString() ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'titleQuestion': titleQuestion,
      'Question': question,
      'Answer': answer,
    };
  }
}

class PhaseItem {
  final String phaseName;
  final List<QuestionItem> questions;

  PhaseItem({
    required this.phaseName,
    required this.questions,
  });

  factory PhaseItem.fromJson(Map<String, dynamic> json) {
    final rawQs = json['questions'] as List? ?? json['Questions'] as List? ?? [];
    return PhaseItem(
      phaseName: json['phaseName']?.toString() ?? json['phase_name']?.toString() ?? "",
      questions: rawQs.map((q) => QuestionItem.fromJson(q)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'phaseName': phaseName,
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }
}
