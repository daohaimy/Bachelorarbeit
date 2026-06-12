import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

void _initLogging() {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) => print(r.message));
}

String _archToApple(String archName) => archName == 'x64' ? 'x86_64' : archName;

bool _isIosDevice(String? raw) {
  final t = (raw ?? '').toLowerCase();
  return t.contains('device') || t.contains('iphoneos') || t.contains('physical');
}

Directory _pickSliceDir({
  required Directory xcframeworkDir,
  required bool isDevice,
  required String archApple,
  required Logger log,
}) {
  final dirs = xcframeworkDir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .toList();

  bool platformMatch(Directory d) {
    final name = d.path.split(Platform.pathSeparator).last.toLowerCase();
    if (!name.startsWith('ios-')) return false;
    final isSim = name.contains('simulator');
    return isDevice ? !isSim : isSim;
  }

  bool archMatch(Directory d) {
    final name = d.path.split(Platform.pathSeparator).last.toLowerCase();
    return name.contains(archApple.toLowerCase());
  }

  final platform = dirs.where(platformMatch).toList();
  if (platform.isEmpty) {
    throw Exception('No matching iOS slice dirs in ${xcframeworkDir.path}. Found: ${dirs.map((d) => d.path).join(", ")}');
  }

  final arch = platform.where(archMatch).toList();
  final picked = (arch.isNotEmpty) ? arch.first : platform.first;

  log.info('Picked slice: ${picked.path}');
  return picked;
}

File _findFrameworkBinary({
  required Directory sliceDir,
  required String frameworkName,
}) {
  final fwDir = Directory('${sliceDir.path}${Platform.pathSeparator}$frameworkName.framework');
  if (!fwDir.existsSync()) {
    throw Exception('Framework dir not found: ${fwDir.path}');
  }
  final bin = File('${fwDir.path}${Platform.pathSeparator}$frameworkName');
  if (!bin.existsSync()) {
    throw Exception('Framework binary not found: ${bin.path}');
  }
  return bin;
}

Future<void> main(List<String> args) async {
  _initLogging();
  final logger = Logger('native_audio');

  await build(args, (input, output) async {
    final os = input.config.code.targetOS;
    if (os != OS.iOS) return;

    final iosRaw = input.config.code.iOS.targetSdk.type.toString().split('.').last;
    final isDevice = _isIosDevice(iosRaw);

    final archApple = _archToApple(input.config.code.targetArchitecture.name);

    // XCFramework liegt hier:
    final xcUri = input.packageRoot.resolve('ios/AudioKit.xcframework');
    final xcDir = Directory.fromUri(xcUri);
    if (!xcDir.existsSync()) {
      throw Exception('XCFramework not found at: ${xcDir.path}');
    }

    const frameworkName = 'AudioKit'; // muss genau so heißen wie AudioKit.framework/AudioKit
    final sliceDir = _pickSliceDir(
      xcframeworkDir: xcDir,
      isDevice: isDevice,
      archApple: archApple,
      log: logger,
    );

    final binary = _findFrameworkBinary(sliceDir: sliceDir, frameworkName: frameworkName);
    logger.info('Using binary: ${binary.path}');

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'audiokit',
        linkMode: DynamicLoadingBundled(),
        file: binary.uri,
      ),
    );
  });
}
