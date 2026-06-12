import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureAudioPermissions() async {
  final micStatusBefore = await Permission.microphone.status;
  final speechStatusBefore = await Permission.speech.status;

  print('mic before: $micStatusBefore');
  print('speech before: $speechStatusBefore');

  final mic = await Permission.microphone.request();
  final speech = await Permission.speech.request();

  print('mic after: $mic');
  print('speech after: $speech');

  return mic.isGranted && speech.isGranted;
}
