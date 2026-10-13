class VapiTranscriptMessage {
  final String speaker;
  final String text;
  final bool isPartial;
  final bool isConversationUpdate;

  VapiTranscriptMessage({
    required this.speaker,
    required this.text,
    this.isPartial = false,
    this.isConversationUpdate = false,
  });
}

enum VapiCallState {
  idle,
  connecting,
  active,
  ended,
  error,
}
