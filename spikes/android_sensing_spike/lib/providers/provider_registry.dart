import '../core/location/location_provider.dart';
import 'fbg_location_provider.dart';
import 'tracelet_location_provider.dart';

/// 比較対象の位置情報プロバイダの種類。
enum ProviderKind {
  /// flutter_background_geolocation
  fbg,

  /// tracelet
  tracelet,
}

/// [ProviderKind] に対応する [LocationProvider] の新しいインスタンスを作る。
///
/// __重要__: このアプリでは同時に起動して良いプロバイダは常に 1 つだけ。
/// flutter_background_geolocation / tracelet はどちらも Android では
/// 常駐通知付きのフォアグラウンドサービスとして動作するため、
/// 2 つを同時に走らせるとバッテリー消費が二重にかかり、
/// 「どちらが省電力か」を比較するという本スパイクの目的が成立しなくなる。
///
/// そのため呼び出し側は、新しいプロバイダを [createLocationProvider] で
/// 作って [LocationProvider.start] する前に、必ず直前まで使っていた
/// プロバイダに対して [LocationProvider.stop] → [LocationProvider.dispose]
/// の順で呼び出し、計測とフォアグラウンドサービスを完全に停止させてから
/// 切り替えること。
LocationProvider createLocationProvider(ProviderKind kind) {
  switch (kind) {
    case ProviderKind.fbg:
      return FbgLocationProvider();
    case ProviderKind.tracelet:
      return TraceletLocationProvider();
  }
}

/// UI 表示用の人間可読なラベルを返す。
String labelOf(ProviderKind kind) {
  switch (kind) {
    case ProviderKind.fbg:
      return 'flutter_background_geolocation';
    case ProviderKind.tracelet:
      return 'tracelet';
  }
}
