import 'dart:convert';
import 'dart:io';

/// JSON Lines (1 行 1 JSON オブジェクト) 形式でファイルに追記していくシンク。
///
/// このアプリは OS によって突然プロセスを kill されうる前提 (バックグラウンド
/// 計測の検証中) のため、「書き込んだはずのデータが消える」ことを防ぐ耐障害性を
/// 最優先する。そのため:
///
/// - `File.openWrite(mode: FileMode.append)` (バッファリングされる StreamSink) は
///   使わず、[RandomAccessFile] を append モードで開いて都度 [RandomAccessFile.flush]
///   することで、書き込みごとに OS バッファへ確実に反映させる。
/// - 複数の [append] 呼び出しが同時に来ても行が混ざらないよう、内部で
///   `Future` を連結した簡易ミューテックスで直列化する。
class JsonlLogSink {
  JsonlLogSink(this._file);

  final File _file;

  RandomAccessFile? _raf;

  /// 直列化用の Future チェーン (簡易ミューテックス)。
  Future<void> _writeChain = Future<void>.value();

  int _malformedLineCount = 0;

  /// 直近の [readAll] で検出した壊れた行の数。
  int get malformedLineCount => _malformedLineCount;

  Future<RandomAccessFile> _ensureOpen() async {
    final existing = _raf;
    if (existing != null) return existing;
    if (!await _file.parent.exists()) {
      await _file.parent.create(recursive: true);
    }
    final raf = await _file.open(mode: FileMode.append);
    _raf = raf;
    return raf;
  }

  /// 1 件の JSON オブジェクトを 1 行として追記する。
  ///
  /// 呼び出しが重なった場合でも、内部の Future チェーンにより
  /// 書き込みが 1 件ずつ順番に (直列に) 実行される。
  Future<void> append(Map<String, dynamic> json) {
    final pending = _writeChain.then((_) => _writeLine(json));
    // このコールの失敗でチェーン全体が止まらないよう、
    // チェーンの継続用には失敗を握りつぶしたものを使う。
    _writeChain = pending.then((_) {}, onError: (_) {});
    return pending;
  }

  Future<void> _writeLine(Map<String, dynamic> json) async {
    final raf = await _ensureOpen();
    final line = '${jsonEncode(json)}\n';
    await raf.writeString(line);
    await raf.flush();
  }

  /// ファイルをクローズする。保留中の書き込みが完了するのを待ってから閉じる。
  Future<void> close() async {
    await _writeChain;
    final raf = _raf;
    _raf = null;
    if (raf != null) {
      await raf.close();
    }
  }

  /// ファイル全体を読み込み、各行を JSON オブジェクトとしてパースする。
  ///
  /// パースに失敗した行 (空行を除く) はスキップし、その件数を
  /// [malformedLineCount] として保持する。
  Future<List<Map<String, dynamic>>> readAll() async {
    var malformed = 0;
    final result = <Map<String, dynamic>>[];
    if (!await _file.exists()) {
      _malformedLineCount = 0;
      return result;
    }
    final lines = await _file.readAsLines();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        } else {
          malformed++;
        }
      } on FormatException {
        malformed++;
      }
    }
    _malformedLineCount = malformed;
    return result;
  }
}
