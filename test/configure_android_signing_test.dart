import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String? _findPowerShellExecutable() {
  final candidates = Platform.isWindows
      ? const ['pwsh.exe', 'powershell.exe']
      : const ['pwsh'];
  final lookupCommand = Platform.isWindows ? 'where' : 'which';
  for (final candidate in candidates) {
    final result = Process.runSync(
      lookupCommand,
      [candidate],
      runInShell: true,
    );
    if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
      return candidate;
    }
  }
  return null;
}

Future<ProcessResult> _runSigningScript({
  required String powerShell,
  required String keyPropertiesPath,
  required String keystorePath,
  required Map<String, String> secrets,
  String storeFile = 'custom-release.jks',
}) {
  final environment = {
    'ANDROID_KEYSTORE_BASE64': '',
    'ANDROID_STORE_PASSWORD': '',
    'ANDROID_KEY_ALIAS': '',
    'ANDROID_KEY_PASSWORD': '',
    ...secrets,
  };
  return Process.run(
    powerShell,
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'scripts/configure_android_signing.ps1',
      '-KeyPropertiesPath',
      keyPropertiesPath,
      '-KeystorePath',
      keystorePath,
      '-StoreFile',
      storeFile,
    ],
    environment: environment,
  );
}

void main() {
  test('Android signing script skips only when no signing secrets exist',
      () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for signing script tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_signing_empty_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final keyProperties = '${temp.path}${Platform.pathSeparator}key.properties';
    final keystore = '${temp.path}${Platform.pathSeparator}release.jks';
    final result = await _runSigningScript(
      powerShell: powerShell,
      keyPropertiesPath: keyProperties,
      keystorePath: keystore,
      secrets: const {},
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout.toString(),
      contains('Android release signing secrets are not configured'),
    );
    expect(File(keyProperties).existsSync(), false);
    expect(File(keystore).existsSync(), false);
  });

  test('Android signing script rejects partial signing secrets', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for signing script tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_signing_partial_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final keyProperties = '${temp.path}${Platform.pathSeparator}key.properties';
    final keystore = '${temp.path}${Platform.pathSeparator}release.jks';
    final result = await _runSigningScript(
      powerShell: powerShell,
      keyPropertiesPath: keyProperties,
      keystorePath: keystore,
      secrets: const {
        'ANDROID_STORE_PASSWORD': 'store-password',
      },
    );

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}',
      contains('Android release signing secrets are incomplete'),
    );
    expect(File(keyProperties).existsSync(), false);
    expect(File(keystore).existsSync(), false);
  });

  test('Android signing script writes complete signing secrets', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for signing script tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_signing_complete_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final keyProperties = '${temp.path}${Platform.pathSeparator}key.properties';
    final keystore = '${temp.path}${Platform.pathSeparator}release.jks';
    final keystoreBytes = [0x52, 0x50, 0x54, 0x44];
    final result = await _runSigningScript(
      powerShell: powerShell,
      keyPropertiesPath: keyProperties,
      keystorePath: keystore,
      secrets: {
        'ANDROID_KEYSTORE_BASE64': base64Encode(keystoreBytes),
        'ANDROID_STORE_PASSWORD': 'store-password',
        'ANDROID_KEY_ALIAS': 'repapertodo',
        'ANDROID_KEY_PASSWORD': 'key-password',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(File(keystore).readAsBytesSync(), keystoreBytes);
    expect(
      File(keyProperties).readAsStringSync().replaceAll('\r\n', '\n'),
      [
        'storeFile=custom-release.jks',
        'storePassword=store-password',
        'keyAlias=repapertodo',
        'keyPassword=key-password',
        '',
      ].join('\n'),
    );
  });

  test('Android signing script rejects unsafe storeFile values', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for signing script tests.');
      return;
    }

    for (final caseData in const [
      (
        storeFile: '../release.jks',
        expected: 'Android signing storeFile must not contain dot-segments',
      ),
      (
        storeFile: 'release-*.jks',
        expected:
            'Android signing storeFile must not contain wildcard characters',
      ),
    ]) {
      final temp = await Directory.systemTemp.createTemp(
        'repapertodo_signing_storefile_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final keyProperties =
          '${temp.path}${Platform.pathSeparator}key.properties';
      final keystore = '${temp.path}${Platform.pathSeparator}release.jks';
      final result = await _runSigningScript(
        powerShell: powerShell,
        keyPropertiesPath: keyProperties,
        keystorePath: keystore,
        storeFile: caseData.storeFile,
        secrets: {
          'ANDROID_KEYSTORE_BASE64': base64Encode([0x52, 0x50, 0x54, 0x44]),
          'ANDROID_STORE_PASSWORD': 'store-password',
          'ANDROID_KEY_ALIAS': 'repapertodo',
          'ANDROID_KEY_PASSWORD': 'key-password',
        },
      );

      expect(result.exitCode, isNot(0));
      expect('${result.stdout}\n${result.stderr}', contains(caseData.expected));
      expect(File(keyProperties).existsSync(), false);
      expect(File(keystore).existsSync(), false);
    }
  });

  test('Android signing script rejects absolute storeFile values', () async {
    final powerShell = _findPowerShellExecutable();
    if (powerShell == null) {
      markTestSkipped('PowerShell is unavailable for signing script tests.');
      return;
    }

    final temp = await Directory.systemTemp.createTemp(
      'repapertodo_signing_absolute_storefile_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final keyProperties = '${temp.path}${Platform.pathSeparator}key.properties';
    final keystore = '${temp.path}${Platform.pathSeparator}release.jks';
    final absoluteStoreFile =
        '${temp.path}${Platform.pathSeparator}absolute-release.jks';
    final result = await _runSigningScript(
      powerShell: powerShell,
      keyPropertiesPath: keyProperties,
      keystorePath: keystore,
      storeFile: absoluteStoreFile,
      secrets: {
        'ANDROID_KEYSTORE_BASE64': base64Encode([0x52, 0x50, 0x54, 0x44]),
        'ANDROID_STORE_PASSWORD': 'store-password',
        'ANDROID_KEY_ALIAS': 'repapertodo',
        'ANDROID_KEY_PASSWORD': 'key-password',
      },
    );

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}\n${result.stderr}',
      contains(
        'Android signing storeFile must be relative to the Android project',
      ),
    );
    expect(File(keyProperties).existsSync(), false);
    expect(File(keystore).existsSync(), false);
  });
}
