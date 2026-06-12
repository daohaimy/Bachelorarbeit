import 'package:native_kontaktbericht/native_kontaktbericht.dart';

/// Top-level functions für compute()
Map<String, dynamic> ffiExtract(String freeText) {
  final res = extractFromFreeText(freeText);
  return (res as Map).cast<String, dynamic>();
}

Map<String, dynamic> ffiAnswer(Map<String, dynamic> payload) {
  final res = answerFollowup(
    originalFreeText: payload['originalFreeText'] as String,
    followupAnswer: payload['followupAnswer'] as String,
    currentBerichtDto: (payload['currentBerichtDto'] as Map).cast<String, dynamic>(),
  );
  return (res as Map).cast<String, dynamic>();
}

bool ffiSave(Map<String, dynamic> dto) {
  return saveKontaktbericht(dto);
}
