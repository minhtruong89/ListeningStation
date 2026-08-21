class VapiTranscriptMessage {
  final String speaker;
  final String text;
  final bool isPartial;

  VapiTranscriptMessage({
    required this.speaker,
    required this.text,
    this.isPartial = false,
  });
}

enum VapiCallState {
  idle,
  connecting,
  active,
  ended,
  error,
}
