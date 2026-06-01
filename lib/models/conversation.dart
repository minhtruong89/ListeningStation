class ConversationMessage {
  final String sender; // "Patient", "AI", "System"
  final String content;
  final DateTime timestamp;

  ConversationMessage({
    this.sender = 'System',
    this.content = '',
    required this.timestamp,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      sender: json['Sender'] ?? json['sender'] ?? 'System',
      content: json['Content'] ?? json['content'] ?? '',
      timestamp: json['Timestamp'] != null
          ? DateTime.parse(json['Timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Sender': sender,
      'Content': content,
      'Timestamp': timestamp.toIso8601String(),
    };
  }
}

class ConversationSession {
  final int id;
  final int operatorId;
  final DateTime startTime;
  final List<ConversationMessage> messages;
  final String? summaryJson;

  ConversationSession({
    this.id = 0,
    required this.operatorId,
    required this.startTime,
    required this.messages,
    this.summaryJson,
  });

  factory ConversationSession.fromJson(Map<String, dynamic> json) {
    var rawMsgs = json['Messages'] ?? json['messages'] ?? [];
    List<ConversationMessage> parsedMsgs = [];
    for (var m in rawMsgs) {
      parsedMsgs.add(ConversationMessage.fromJson(m));
    }

    return ConversationSession(
      id: json['Id'] ?? json['id'] ?? 0,
      operatorId: json['OperatorId'] ?? json['operator_id'] ?? 0,
      startTime: json['StartTime'] != null
          ? DateTime.parse(json['StartTime'])
          : DateTime.now(),
      messages: parsedMsgs,
      summaryJson: json['SummaryJson'] ?? json['summary_json'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'OperatorId': operatorId,
      'StartTime': startTime.toIso8601String(),
      'Messages': messages.map((m) => m.toJson()).toList(),
      'SummaryJson': summaryJson,
    };
  }
}
