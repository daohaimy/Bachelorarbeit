import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'native_kontaktbericht_bindings_generated.dart' as gen;

String _takeAndFree(ffi.Pointer<ffi.Char> p) {
  final s = p.cast<Utf8>().toDartString();
  gen.kb_free(p.cast());
  return s;
}

Map<String, dynamic> extractFromFreeText(String freeText) {
  final inJson = jsonEncode({'freeText': freeText}).toNativeUtf8();
  final outPtr = gen.kb_extract_json(inJson.cast());
  malloc.free(inJson);

  final outJson = _takeAndFree(outPtr);
  return jsonDecode(outJson) as Map<String, dynamic>;
}

Map<String, dynamic> answerFollowup({
  required String originalFreeText,
  required String followupAnswer,
  required Map<String, dynamic> currentBerichtDto,
}) {
  final inMap = {
    'originalFreeText': originalFreeText,
    'followupAnswer': followupAnswer,
    'currentBericht': currentBerichtDto,
  };

  final inJson = jsonEncode(inMap).toNativeUtf8();
  final outPtr = gen.kb_answer_followup_json(inJson.cast());
  malloc.free(inJson);

  final outJson = _takeAndFree(outPtr);
  return jsonDecode(outJson) as Map<String, dynamic>;
}

bool saveKontaktbericht(Map<String, dynamic> berichtDto) {
  final inJson = jsonEncode({'bericht': berichtDto}).toNativeUtf8();
  final outPtr = gen.kb_save_json(inJson.cast());
  malloc.free(inJson);

  final outJson = _takeAndFree(outPtr);
  final map = jsonDecode(outJson) as Map<String, dynamic>;
  return map['ok'] == true;
}

List<Map<String, dynamic>> listKontaktberichte() {
  final outPtr = gen.kb_list_json();
  final outJson = _takeAndFree(outPtr);
  final map = jsonDecode(outJson) as Map<String, dynamic>;
  final items = (map['items'] as List? ?? const []);
  return items.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

bool deleteKontaktbericht(String id) {
  final inJson = jsonEncode({'id': id}).toNativeUtf8();
  final outPtr = gen.kb_delete_json(inJson.cast());
  malloc.free(inJson);

  final outJson = _takeAndFree(outPtr);
  final map = jsonDecode(outJson) as Map<String, dynamic>;
  return map['ok'] == true;
}
