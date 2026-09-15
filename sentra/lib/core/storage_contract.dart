import 'models.dart';

abstract interface class AppStorage {
  Future<ApiSettings> readSettings();
  Future<void> writeSettings(ApiSettings settings);
  Future<List<Sentence>> readHistory();
  Future<void> writeHistory(List<Sentence> sentences);
}
