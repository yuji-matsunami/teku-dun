import 'dart:convert';
import 'dart:io';

import '../models/session_meta.dart';
import 'jsonl_log_sink.dart';

/// 計測セッションのディレクトリ群をディスク上で管理するクラス。
///
/// レイアウトは以下の通り:
/// ```
/// <root>/sessions/<sessionId>/events.jsonl
/// <root>/sessions/<sessionId>/meta.json
/// ```
///
/// コアレイヤーをテスト可能に保つため、ルートディレクトリは
/// コンストラクタで注入する (`path_provider` などのプラットフォーム
/// 依存パッケージにはここでは一切依存しない)。実際のアプリ用ドキュメント
/// ディレクトリを使いたい場合は、下部の [SessionStore.openDefault] を参照。
class SessionStore {
  SessionStore(this._root);

  final Directory _root;

  Directory get _sessionsDir => _join(_root, const ['sessions']);

  Directory _sessionDir(String id) => _join(_sessionsDir, [id]);

  File _eventsFile(String id) => File(_joinPath(_sessionDir(id).path, 'events.jsonl'));

  File _metaFile(String id) => File(_joinPath(_sessionDir(id).path, 'meta.json'));

  /// 新しいセッションを作成し、ディレクトリと meta.json を用意する。
  /// セッション ID は開始時刻 (UTC) とプロバイダ ID から生成する
  /// (例: "20260822-090000-fbg")。
  Future<SessionMeta> createSession({
    required String providerId,
    required Map<String, dynamic> deviceInfo,
    required Map<String, dynamic> providerConfig,
    int? batteryAtStart,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final id = '${_formatTimestamp(startedAt)}-$providerId';
    final meta = SessionMeta(
      id: id,
      providerId: providerId,
      startedAt: startedAt,
      deviceInfo: deviceInfo,
      providerConfig: providerConfig,
      batteryAtStart: batteryAtStart,
    );
    await _sessionDir(id).create(recursive: true);
    await updateMeta(meta);
    return meta;
  }

  /// 指定セッションの events.jsonl に書き込むための [JsonlLogSink] を返す。
  /// セッションディレクトリが未作成でも、呼び出し時に自動的に作成する。
  JsonlLogSink sinkFor(String sessionId) {
    final dir = _sessionDir(sessionId);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return JsonlLogSink(_eventsFile(sessionId));
  }

  /// meta.json を上書き保存する。
  Future<void> updateMeta(SessionMeta meta) async {
    await _sessionDir(meta.id).create(recursive: true);
    await _metaFile(meta.id).writeAsString(jsonEncode(meta.toJson()));
  }

  /// 保存されている全セッションのメタ情報を、開始時刻が新しい順に返す。
  /// 壊れた meta.json を持つセッションは無視する。
  Future<List<SessionMeta>> listSessions() async {
    final dir = _sessionsDir;
    if (!await dir.exists()) return const [];
    final metas = <SessionMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final metaFile = File(_joinPath(entity.path, 'meta.json'));
      if (!await metaFile.exists()) continue;
      try {
        final json = jsonDecode(await metaFile.readAsString());
        if (json is Map<String, dynamic>) {
          metas.add(SessionMeta.fromJson(json));
        }
      } on FormatException {
        // 壊れた meta.json はスキップする。
      }
    }
    metas.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return metas;
  }

  /// 指定セッションの events.jsonl を全件読み込む。
  Future<List<Map<String, dynamic>>> readEvents(String sessionId) async {
    final sink = JsonlLogSink(_eventsFile(sessionId));
    try {
      return await sink.readAll();
    } finally {
      await sink.close();
    }
  }

  /// セッションのディレクトリごと削除する。
  Future<void> deleteSession(String id) async {
    final dir = _sessionDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// エクスポート用に events.jsonl の [File] を返す。
  /// (このスパイクでは events.jsonl 自体が既に JSONL 形式のため、
  /// コピーは行わずファイル参照をそのまま返す。)
  Future<File> exportSessionAsJsonl(String id) async {
    return _eventsFile(id);
  }

  static Directory _join(Directory base, List<String> parts) {
    return Directory(parts.fold(base.path, _joinPath));
  }

  static String _joinPath(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) {
      return '$a$b';
    }
    return '$a${Platform.pathSeparator}$b';
  }

  static String _formatTimestamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        '-${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }

  /// アプリの既定のドキュメントディレクトリを使う [SessionStore] を開くための、
  /// 独立した小さなファクトリメソッド。
  ///
  /// [SessionStore] 本体はテスト容易性のため `path_provider` などの
  /// プラットフォーム依存パッケージに一切依存させない設計としている。
  /// 本メソッドはその方針を保ったまま、ディレクトリ解決処理だけを
  /// 呼び出し側から関数として注入してもらう形にしている。
  ///
  /// 現時点では `path_provider` が pubspec.yaml に追加されていないため、
  /// 実際のアプリ (main.dart など、このエージェントの管轄外) から使う場合は、
  /// まず `path_provider` を依存関係に追加したうえで、次のように呼び出すこと:
  ///
  /// ```dart
  /// import 'package:path_provider/path_provider.dart';
  ///
  /// final store = await SessionStore.openDefault(
  ///   resolveDir: getApplicationDocumentsDirectory,
  /// );
  /// ```
  static Future<SessionStore> openDefault({
    required Future<Directory> Function() resolveDir,
  }) async {
    final dir = await resolveDir();
    return SessionStore(dir);
  }
}
