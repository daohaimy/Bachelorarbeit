import 'package:native_audio/native_audio.dart';

class AudioChannel {
  Stream<Map<String, dynamic>> events() => NativeAudio.events();

  Future<void> toggleFreeTextMic() => NativeAudio.toggleFreeTextMic();
  Future<void> toggleFollowupMic() => NativeAudio.toggleFollowupMic();
  Future<void> stopStt() => NativeAudio.stopStt();

  Future<void> speak(String text) => NativeAudio.speak(text);
  Future<void> stopSpeak() => NativeAudio.stopSpeak();

  Future<void> speakPendingQuestionAuto(String? question, {bool auto = true}) async {
    if (question != null && question.trim().isNotEmpty) {
      await NativeAudio.speak(question);
    }
  }
}
