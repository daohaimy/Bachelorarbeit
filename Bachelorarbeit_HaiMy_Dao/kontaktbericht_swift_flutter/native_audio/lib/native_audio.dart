import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'native_audio_bindings_generated.dart' as b;

/// Events kommen per Polling von `ak_get_state_json`, aber NICHT im UI-Isolate.
class NativeAudio {
  NativeAudio._();

  static final _events = StreamController<Map<String, dynamic>>.broadcast();

  static Isolate? _iso;
  static ReceivePort? _rx;
  static SendPort? _tx;

  static String _lastStateJson = '';

  /// Ein Stream. nur EIN Event pro Tick wird gesendet:
  /// {"type":"state","isAuthorized":bool,"target":"freeText|followup|none","isSpeaking":bool,"text":String,"error":dynamic}
  static Stream<Map<String, dynamic>> events() {
    start(); // polling starten sobald jemand lauscht
    return _events.stream;
  }

  static void start({int intervalMs = 350}) {
    if (_iso != null) return;

    _rx = ReceivePort();
    Isolate.spawn(_pollIsolateEntry, _rx!.sendPort).then((iso) {
      _iso = iso;
    });

    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        _tx!.send({'cmd': 'start', 'intervalMs': intervalMs});
        return;
      }
      if (msg is String) {
        _handleStateJson(msg);
      }
    });
  }

  static void dispose() {
    _tx?.send({'cmd': 'stop'});
    _rx?.close();
    _rx = null;
    _tx = null;
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
    _lastStateJson = '';
  }

  // ----------- Public commands -----------

  static Future<void> toggleFreeTextMic() async {
    await Isolate.run(() {
      _call1(b.ak_toggle_mic_json, {'target': 'freeText'});
    });
  }

  static Future<void> toggleFollowupMic() async {
    await Isolate.run(() {
      _call1(b.ak_toggle_mic_json, {'target': 'followup'});
    });
  }

  static Future<void> stopStt() async {
    await Isolate.run(() {
      _call0(b.ak_stop_stt_json);
    });
  }

  static Future<void> speak(String text) async {
    await Isolate.run(() {
      _call1(b.ak_speak_json, {'text': text});
    });
  }

  static Future<void> stopSpeak() async {
    await Isolate.run(() {
      _call0(b.ak_stop_speak_json);
    });
  }

  // ----------- Internals -----------

  static void _handleStateJson(String s) {
    if (s == _lastStateJson) return;
    _lastStateJson = s;

    final decoded = jsonDecode(s);
    if (decoded is! Map) return;
    final state = decoded.cast<String, dynamic>();

    _events.add({
      'type': 'state',
      'isAuthorized': state['isAuthorized'] == true,
      'target': (state['activeMic'] ?? 'none').toString(),
      'isSpeaking': state['isSpeaking'] == true,
      'text': (state['transcript'] ?? '').toString(),
      'error': state['error'],
    });
  }

  static Map<String, dynamic> _call0(Pointer<Char> Function() fn) {
    final p = fn();
    try {
      final s = p.cast<Utf8>().toDartString();
      final obj = jsonDecode(s);
      return (obj is Map) ? obj.cast<String, dynamic>() : {'error': 'invalid_json'};
    } finally {
      b.ak_free(p);
    }
  }

  static Map<String, dynamic> _call1(
    Pointer<Char> Function(Pointer<Char>) fn,
    Map<String, dynamic> payload,
  ) {
    final inStr = jsonEncode(payload);
    final inPtr = inStr.toNativeUtf8().cast<Char>();
    final p = fn(inPtr);
    malloc.free(inPtr);

    try {
      final s = p.cast<Utf8>().toDartString();
      final obj = jsonDecode(s);
      return (obj is Map) ? obj.cast<String, dynamic>() : {'error': 'invalid_json'};
    } finally {
      b.ak_free(p);
    }
  }

  // ----------- Isolate Entry -----------

  static Future<bool> requestPermissions() async {
    final json = await Isolate.run(() {
      final p = b.ak_request_permissions_json();
      try {
        return p.cast<Utf8>().toDartString();
      } finally {
        b.ak_free(p);
      }
    });

    final obj = jsonDecode(json);
    return obj is Map && obj['ok'] == true;
  }

  static void _pollIsolateEntry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    Timer? t;

    void tick() {
      final p = b.ak_get_state_json();
      try {
        final s = p.cast<Utf8>().toDartString();
        mainSendPort.send(s);
      } finally {
        b.ak_free(p);
      }
    }

    port.listen((msg) {
      if (msg is Map && msg['cmd'] == 'start') {
        final interval = (msg['intervalMs'] as int?) ?? 350;
        t?.cancel();
        t = Timer.periodic(Duration(milliseconds: interval), (_) => tick());
        tick(); // sofort
      } else if (msg is Map && msg['cmd'] == 'stop') {
        t?.cancel();
        port.close();
      }
    });
  }
}