# android_sensing_spike

M0-I1（[Issue #5](https://github.com/yuji-matsunami/teku-dun/issues/5)）の検証用スパイク。

Android 実機で、**画面ロック中も位置情報と歩数を取得できるか**を確認する。
あわせて [技術選定](../../docs/tech-stack.md) の未決事項である
「`tracelet` が `flutter_background_geolocation` の代替として実用に足るか」を判断するため、
同一端末・同一設定・同一ログ形式で両者を比較できるようにしてある。

**実行手順と比較表は [docs/verification/m0-i1-android-sensing.md](../../docs/verification/m0-i1-android-sensing.md) にある。**
このREADMEはコードの構成だけを説明する。

## これは製品コードではない

検証が終われば役目を終える使い捨てのアプリである。Issue #4 で作る最小基盤とは独立しており、
Drift への保存も API 送信も行わない（Issue #5 のスコープ外）。

## 構成

```
lib/
  core/                     位置情報ライブラリに依存しない層
    models/
      location_sample.dart    両ライブラリの位置情報を正規化する共通スキーマ
      tracking_event.dart     権限・モーション変化・歩数などの出来事
      session_meta.dart       1計測セッションのメタ情報
    log/
      jsonl_log_sink.dart     1行1レコードで即時flushするログ書き込み
      session_store.dart      セッションのディレクトリ管理
    metrics/
      session_metrics.dart    取得間隔・欠損・距離・精度・電池消費の算出
    location/
      location_provider.dart  プロバイダの抽象インターフェース
  providers/
    fbg_location_provider.dart       flutter_background_geolocation 実装
    tracelet_location_provider.dart  tracelet 実装
    provider_registry.dart           切り替えのためのファクトリ
  health/
    health_steps_reader.dart  Health Connect からの歩数取得
  device/
    battery_sampler.dart      電池残量の取得と定期記録
    device_info_probe.dart    端末情報（OEMごとの省電力差を記録するため）
  ui/                         画面とセッション制御
```

### 比較を成立させるための設計

1. **共通スキーマへ正規化する。** 2つのライブラリは位置オブジェクトのフィールド名も
   単位も活動種別の表現も異なる。受け取った直後に `LocationSample` へ変換し、
   以降は同じ経路で扱う。電池残量（両者とも 0.0〜1.0）は 0〜100 の整数へ、
   活動種別は `on_foot` のような同一の語彙へ揃えている。

2. **JSONL へ即時 flush する。** 散歩中に OS がアプリを停止させても、そこまでのログが残る。
   まとめ書きにすると、欠損の有無そのものが測れない。

3. **集計はアプリ内で行う。** 散歩から戻った直後に取得間隔・欠損・電池消費が読めれば、
   比較表をその場で埋められる。

4. **同時に走らせない。** 両ライブラリとも常駐通知付きのフォアグラウンドサービスとして動く。
   2つ同時に動かすと電池消費が二重にかかり、比較の意味がなくなる。
   プロバイダ切り替え時は、必ず前のものを `stop()` → `dispose()` してから次を開始する。

5. **計測設定を揃える。** 両プロバイダとも精度 high、`distanceFilter` 10m、
   更新間隔 5000ms、`stopOnTerminate: false`、`startOnBoot: false` で固定している。

## 依存パッケージについて

| パッケージ | 補足 |
| --- | --- |
| `flutter_background_geolocation` 5.5.0 | Maven Central 配信のため追加リポジトリ不要。**DEBUG ビルドはライセンス不要**で全機能が動く。リリースビルドには $399 のライセンスが要る |
| `tracelet` 3.8.7 | Apache-2.0。単独開発者による新しいパッケージで実績は乏しい。まさにそこを実測で確かめるのが本スパイクの目的 |
| `health` 13.3.2 | Android は Health Connect 経由。`MainActivity` が `FlutterFragmentActivity` を継承している必要がある |
| `permission_handler` 12.0.3 | 13.x 系は `compileSdk 37` を要求するが、Android SDK 側には `android-37.0` しか存在せず Gradle が解決できない。`compileSdk 35` を宣言する 12.x に固定している（本アプリのビルドは compileSdk 36） |

`minSdk` は 26。`health` と `tracelet` がいずれも要求する。

## 確認済みの事項

- `flutter_background_geolocation` と `tracelet` を同一アプリに同居させても、
  マニフェストマージは衝突しない（DEBUG APK のビルドで確認）
- マージ後のマニフェストに `FOREGROUND_SERVICE_LOCATION` と
  `foregroundServiceType="location"` のサービスが正しく含まれる
