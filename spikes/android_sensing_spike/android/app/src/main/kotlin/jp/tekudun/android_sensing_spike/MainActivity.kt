package jp.tekudun.android_sensing_spike

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * health パッケージの Health Connect 権限フローは registerForActivityResult を使うため、
 * FlutterActivity ではなく FlutterFragmentActivity を継承する必要がある。
 */
class MainActivity : FlutterFragmentActivity()
