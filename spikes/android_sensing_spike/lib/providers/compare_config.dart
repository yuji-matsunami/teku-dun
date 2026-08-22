/// 2つのプロバイダを公平に比較するための共通設定値。
///
/// __必ず両プロバイダがこの1か所を参照すること。__
/// 以前はプロバイダごとに同じ意味の定数を private に持っていたが、
/// コンパイル時の結び付きが無いため、片方だけ書き換えても誰も気付かない。
/// 精度や間隔が食い違ったまま計測すると、その差をライブラリの性能差として
/// 読んでしまい、「$399 を払うか」という判断そのものを誤らせる。
class CompareConfig {
  const CompareConfig._();

  /// 位置情報の発火間隔を決める移動距離のしきい値 (メートル)。
  ///
  /// 両プロバイダで実際に効いている、唯一の比較可能なつまみ。
  static const double distanceFilterMeters = 10.0;

  /// 位置情報の更新間隔 (ミリ秒)。
  ///
  /// __fbg では効かない。__ fbg 公式ドキュメントに
  /// 「`locationUpdateInterval` を使うには `distanceFilter: 0` にする必要がある。
  /// `distanceFilter` が `locationUpdateInterval` を上書きするからだ」と明記
  /// されている。本スパイクは `distanceFilter` を 10m に揃えているため、
  /// fbg 側は移動距離駆動で発火する。
  ///
  /// tracelet 側の `AndroidConfig.locationUpdateInterval` には同種の
  /// 上書き注記が無いため、そちらでは効いている可能性がある。
  /// この非対称性は取得間隔の比較時に必ず考慮すること。
  static const int locationUpdateIntervalMs = 5000;

  /// アプリ終了時に計測を止めないか。
  ///
  /// false のままにすると、アプリが OS に落とされた時点で計測も終わり、
  /// 「画面ロック中に計測が続くか」という検証条件を満たせない。
  static const bool stopOnTerminate = false;

  /// 端末起動時に計測を自動再開するか。
  ///
  /// 検証中に意図せず計測が始まると、電池消費の比較が汚れる。
  /// 明示的に開始したときだけ動かす。
  static const bool startOnBoot = false;
}
