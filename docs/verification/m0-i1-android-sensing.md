# M0-I1 Android バックグラウンド位置・Health Connect 収集の検証

対応 Issue: [#5](https://github.com/yuji-matsunami/teku-dun/issues/5)

## 目的

Android 実機で、**画面ロック中も**位置情報と歩数を取得できるかを確認する。

あわせて [技術選定](../tech-stack.md) の未決事項である
「`tracelet` が `flutter_background_geolocation` の代替として実用に足るか」に判断材料を与える。

## 検証しないこと

iOS、24時間計測、本番向け最適化、Drift への保存、API 送信。

## 成果物

| 成果物 | 場所 |
| --- | --- |
| 検証用アプリ | [`spikes/android_sensing_spike`](../../spikes/android_sensing_spike) |
| 実行手順 | 本書「手順」 |
| 比較表 | 本書「比較結果」 |

---

## 検証アプリの設計

同一アプリ内でバックグラウンド位置ライブラリを切り替えられるようにし、
**両候補を同一端末・同一フォーマットのログで比較できる**ようにする。

```
[ UI ]  プロバイダ選択 / 権限 / セッション開始・停止 / 集計表示 / エクスポート
   |
[ LocationProvider (抽象) ]
   |-- FbgLocationProvider      : flutter_background_geolocation
   |-- TraceletLocationProvider : tracelet
   |
   v
[ LocationSample (共通スキーマ) ] --> [ JsonlLogSink ] --> sessions/<id>/events.jsonl
                                                            + meta.json
   ^
[ HealthStepsReader ] Health Connect の歩数
[ BatterySampler ]    電池残量
```

比較を成立させるうえで重要な点は次の3つ。

1. **共通スキーマに正規化する。** 各ライブラリの位置オブジェクトはフィールド名も単位も異なる。
   受け取った直後に `LocationSample` へ変換し、以降は同じ経路で扱う。
2. **1行1レコードの JSONL へ即時 flush する。** 散歩中に OS がアプリを停止させても、
   そこまでのログが残る。まとめ書きにすると欠損の有無自体が測れない。
3. **集計はアプリ内で行う。** 散歩から戻った直後に取得間隔・欠損・電池消費が読めれば、
   比較表をその場で埋められる。

---

## 手順

（実装完了後に記載）

---

## 比較結果

### 実施条件

| 項目 | 値 |
| --- | --- |
| 端末 |  |
| Android バージョン |  |
| 計測日時 |  |
| 経路・距離 |  |
| 天候・環境（屋外／ビル影など） |  |
| 画面状態 | ロック（ポケット内） |

### 候補比較

| 観点 | `flutter_background_geolocation` | `tracelet` |
| --- | --- | --- |
| 取得サンプル数 |  |  |
| 取得間隔（中央値） |  |  |
| 取得間隔（最大 = 最大欠損） |  |  |
| 欠損率 |  |  |
| 位置精度（中央値） |  |  |
| 移動距離（実測との差） |  |  |
| 電池消費（%/時） |  |  |
| 画面ロック中の継続 |  |  |
| アプリ強制終了後の継続 |  |  |
| 活動種別の取得 |  |  |
| 導入の手間 |  |  |
| 制約・気付き |  |  |

### 権限まわりの挙動

| 権限 | 許可時 | 拒否時 |
| --- | --- | --- |
| 位置（正確な位置・アプリ使用中） |  |  |
| 位置（常に許可 / バックグラウンド） |  |  |
| 身体活動（ACTIVITY_RECOGNITION） |  |  |
| 通知（POST_NOTIFICATIONS） |  |  |
| Health Connect 歩数の読み取り |  |  |

### Health Connect

| 項目 | 結果 |
| --- | --- |
| 歩数を取得できたか |  |
| 歩数の供給元アプリ |  |
| アプリ側の移動距離との整合 |  |
| Health Connect 未インストール時の挙動 |  |

---

## 結論

（計測後に記載）

- 画面ロック中の位置情報取得は成立するか:
- 画面ロック中の歩数取得は成立するか:
- `tracelet` を採用できるか（$399 を回避できるか）:
- M1 へ進むうえでの残課題:
