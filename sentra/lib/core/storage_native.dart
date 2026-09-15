import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

import 'storage_contract.dart';

class LocalStorage implements AppStorage {
  final _secure = const FlutterSecureStorage(
    // Use the macOS login keychain for local builds without a signing team.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  Future<void> _writes = Future.value();
  @override
  Future<ApiSettings> readSettings() async {
    final json = await _secure.read(key: 'sentra.settings.v1');
    return json == null
        ? const ApiSettings()
        : ApiSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<void> writeSettings(ApiSettings settings) => _secure.write(
    key: 'sentra.settings.v1',
    value: jsonEncode(settings.toJson()),
  );
  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/sentences.v1.json',
  );
  @override
  Future<List<Sentence>> readHistory() async {
    final file = await _file();
    if (!await file.exists()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .map((e) => Sentence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> writeHistory(List<Sentence> sentences) {
    // Snapshot before scheduling; serialize writes and replace atomically on iOS.
    final snapshot = jsonEncode(sentences.map((e) => e.toJson()).toList());
    final operation = _writes.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}
