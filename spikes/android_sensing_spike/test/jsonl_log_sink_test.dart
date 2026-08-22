import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:android_sensing_spike/core/log/jsonl_log_sink.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('jsonl_log_sink_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('append した内容を readAll でそのまま読み戻せる', () async {
    final file = File('${tempDir.path}/events.jsonl');
    final sink = JsonlLogSink(file);

    await sink.append({'type': 'event', 'kind': 'sessionStart', 'seq': 0});
    await sink.append({'type': 'location', 'seq': 1, 'latitude': 35.0});
    await sink.append({'type': 'event', 'kind': 'sessionEnd', 'seq': 2});
    await sink.close();

    final reader = JsonlLogSink(file);
    final records = await reader.readAll();
    await reader.close();

    expect(records, hasLength(3));
    expect(records[0]['kind'], 'sessionStart');
    expect(records[1]['latitude'], 35.0);
    expect(records[2]['kind'], 'sessionEnd');
    expect(reader.malformedLineCount, 0);
  });

  test('ファイルが存在しない場合、readAll は空リストを返す', () async {
    final file = File('${tempDir.path}/missing.jsonl');
    final sink = JsonlLogSink(file);

    final records = await sink.readAll();

    expect(records, isEmpty);
    expect(sink.malformedLineCount, 0);
    await sink.close();
  });

  test('壊れた行はスキップされ、malformedLineCount に反映される', () async {
    final file = File('${tempDir.path}/broken.jsonl');
    await file.create(recursive: true);
    await file.writeAsString(
      '{"type":"event","kind":"a"}\n'
      'これは JSON ではない行\n'
      '{"type":"event","kind":"b"}\n'
      '[1,2,3]\n' // Map ではなく List なので不正扱い
      '\n' // 空行はスキップするが不正扱いにはしない
      '{"type":"event","kind":"c"}\n',
    );

    final sink = JsonlLogSink(file);
    final records = await sink.readAll();
    await sink.close();

    expect(records, hasLength(3));
    expect(records.map((r) => r['kind']), ['a', 'b', 'c']);
    expect(sink.malformedLineCount, 2);
  });

  test('同時に多数 append しても行が混ざらず全件正しく書き込まれる', () async {
    final file = File('${tempDir.path}/concurrent.jsonl');
    final sink = JsonlLogSink(file);

    const total = 100;
    final futures = <Future<void>>[];
    for (var i = 0; i < total; i++) {
      // await せずに一気に発火させ、内部の直列化に任せる。
      futures.add(sink.append({'type': 'event', 'kind': 'tick', 'index': i}));
    }
    await Future.wait(futures);
    await sink.close();

    final reader = JsonlLogSink(file);
    final records = await reader.readAll();
    await reader.close();

    expect(records, hasLength(total));
    expect(reader.malformedLineCount, 0);
    final indices = records.map((r) => r['index'] as int).toSet();
    expect(indices, Set<int>.from(List.generate(total, (i) => i)));
  });
}
