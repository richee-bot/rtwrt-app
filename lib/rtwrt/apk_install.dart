import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('rtwrt/update');

/// Downloads a release APK and opens the Android installer.
class ApkInstall {
  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {'User-Agent': 'RTWRT'},
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  static Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    final allowed = await _channel.invokeMethod<bool>('canInstall');
    return allowed ?? false;
  }

  static Future<void> openInstallSettings() {
    return _channel.invokeMethod<void>('openInstallSettings');
  }

  static Future<void> downloadAndInstall(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('App install runs on Android.');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/RTWRT-update.apk');
    if (await file.exists()) await file.delete();
    await _dio.download(url, file.path, onReceiveProgress: onProgress);
    await _channel.invokeMethod<void>('install', {'path': file.path});
  }
}
