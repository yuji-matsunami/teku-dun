import 'package:device_info_plus/device_info_plus.dart';

/// 端末情報を収集するためのラッパー。
///
/// 同じ計測条件でもメーカー (OEM) ごとの電力管理 (バックグラウンド制限・
/// Doze/App Standby の挙動など) が大きく異なるため、バッテリー消費の
/// 比較結果を読むときは「どの端末で測ったか」が欠かせない情報になる。
/// この情報は [SessionMeta.deviceInfo] に格納され、比較表に添えられる。
class DeviceInfoProbe {
  DeviceInfoProbe({DeviceInfoPlugin? plugin}) : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  /// 端末情報を収集する。例外は決して外に投げず、
  /// 失敗した場合は `{'error': ...}` のみを含む Map を返す。
  Future<Map<String, dynamic>> collect() async {
    try {
      final info = await _plugin.androidInfo;
      return <String, dynamic>{
        'manufacturer': info.manufacturer,
        'model': info.model,
        'brand': info.brand,
        'device': info.device,
        'androidSdkInt': info.version.sdkInt,
        'androidRelease': info.version.release,
        'isPhysicalDevice': info.isPhysicalDevice,
      };
    } catch (e) {
      return <String, dynamic>{'error': e.toString()};
    }
  }
}
