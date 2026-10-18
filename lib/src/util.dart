/// Rough token estimate (~4 characters per token) for engines that cannot
/// count exactly.
int estimateTokens(String text) => text.isEmpty ? 0 : (text.length / 4).ceil();
