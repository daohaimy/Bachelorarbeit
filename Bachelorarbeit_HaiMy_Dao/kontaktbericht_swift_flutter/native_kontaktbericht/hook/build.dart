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

Directory _dir(Uri uri) => Directory.fromUri(uri);

File _file(Uri uri) => File.fromUri(uri);

/// Findet in einer .xcframework den besten Slice-Ordner für device/simulator + arch.
Directory _pickXcframeworkSliceDir({
  required Directory xcframeworkDir,
  required bool isDevice,
  required String archApple, // arm64 oder x86_64
  required Logger log,
}) {
  // Alle Unterordner im XCFramework (z.B. ios-arm64, ios-arm64_x86_64-simulator, ...)
  final sliceDirs = xcframeworkDir
      .listSync(followLinks: false)
      .whereType<Directory>()
      .toList();

  bool matchesPlatform(Directory d) {
    final name = d.uri.pathSegments.isNotEmpty
        ? d.uri.pathSegments[d.uri.pathSegments.length - 2] // last dir name
        : d.path.split(Platform.pathSeparator).last;

    final n = name.toLowerCase();
    final isSimSlice = n.contains('simulator');
    if (isDevice && isSimSlice) return false;
    if (!isDevice && !isSimSlice) return false;
    if (!n.startsWith('ios-')) return false;
    return true;
  }

  bool matchesArch(Directory d) {
    final name = d.path.split(Platform.pathSeparator).last.toLowerCase();
    // Slice-Namen enthalten meistens arm64 / x86_64
    return name.contains(archApple.toLowerCase());
  }

  final platformMatches = sliceDirs.where(matchesPlatform).toList();
  if (platformMatches.isEmpty) {
    throw Exception('No matching iOS slice directories found in ${xcframeworkDir.path}');
  }

  // Prefer exact arch match; otherwise fallback to first platform match
  final archMatches = platformMatches.where(matchesArch).toList();
  final picked = (archMatches.isNotEmpty) ? archMatches.first : platformMatches.first;

  log.info('Picked xcframework slice: ${picked.path}');
  return picked;
}

/// In einem Slice-Ordner: finde <Framework>.framework/<Framework> (die Mach-O Binary)
File _findFrameworkBinary({
  required Directory sliceDir,
  required String frameworkName,
}) {
  final frameworkDir = Directory(
    '${sliceDir.path}${Platform.pathSeparator}$frameworkName.framework',
  );
  if (!frameworkDir.existsSync()) {
    throw Exception('Framework dir not found: ${frameworkDir.path}');
  }

  final binary = File(
    '${frameworkDir.path}${Platform.pathSeparator}$frameworkName',
  );
  if (!binary.existsSync()) {
    throw Exception('Framework binary not found: ${binary.path}');
  }
  return binary;
}

Future<void> main(List<String> args) async {
  _initLogging();
  final logger = Logger('native_kontaktbericht');

  await build(args, (input, output) async {
    final os = input.config.code.targetOS;
    if (os != OS.iOS) return; // hier nur iOS, macOS ggf separat behandeln

    final archApple = _archToApple(input.config.code.targetArchitecture.name);

    final iosRaw = input.config.code.iOS.targetSdk.type.toString().split('.').last;
    final isDevice = _isIosDevice(iosRaw);

    // Pfad zu deinem XCFramework im Plugin:
    // native_kontaktbericht/ios/KontaktberichtLogikKit.xcframework
    final xcUri = input.packageRoot.resolve('ios/KontaktberichtLogikKit.xcframework');
    final xcDir = _dir(xcUri);
    if (!xcDir.existsSync()) {
      throw Exception('XCFramework not found at: ${xcDir.path}');
    }

    const frameworkName = 'KontaktberichtLogikKit';

    final sliceDir = _pickXcframeworkSliceDir(
      xcframeworkDir: xcDir,
      isDevice: isDevice,
      archApple: archApple,
      log: logger,
    );

    final binary = _findFrameworkBinary(
      sliceDir: sliceDir,
      frameworkName: frameworkName,
    );

    logger.info('Using framework binary: ${binary.path}');

    // Wichtig: name (= assetId) muss zu ffigen.yaml passen!
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'kontaktbericht_logikkit', // <- gleiches assetId in ffigen.yaml verwenden
        linkMode: DynamicLoadingBundled(),
        file: binary.uri,
      ),
    );
  });
}
