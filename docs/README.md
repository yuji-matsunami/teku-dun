# Documents

プロダクトの方針や開発時の前提を確認するときは、以下のドキュメントを参照してください。

| タイトル | ディスクリプション |
| --- | --- |
| [開発手順](development.md) | macOS + Androidの構成、固定ツール版、代表Task、Android手動確認、DBとスモークテストの副作用をまとめています。 |
| [Agentスキル設計](agent-skills-design.md) | リポジトリ内Agent skillの役割、Task入口、終了条件、副作用の設計をまとめています。 |
| [Go APIアーキテクチャ](api-architecture.md) | Go APIの機能単位の構成、OpenAPI・HTTP・業務処理・PostgreSQLの境界、依存関係、テスト方針をまとめています。 |
| [アプリの方向性](product-overview.md) | アプリのコンセプト、ターゲットユーザー、基本体験、移動、戦闘、育成、装備、ゲーム内経済、安全性に関する長期的な方針をまとめています。 |
| [MVPスコープ](mvp-scope.md) | 初期リリースの目的、MVPに含めるもの・含めないもの、将来の追加候補、未決事項、成立条件をまとめています。 |
| [技術選定](tech-stack.md) | 採用する技術スタック、選定理由、地図と位置情報まわりの方式、開発体制の分担、主要な技術リスクをまとめています。 |

## 検証記録

技術成立性の検証（M0）で実際に確かめた内容と結果は、以下にまとめています。

| タイトル | ディスクリプション |
| --- | --- |
| [M0-I1 Android バックグラウンド位置・Health Connect 収集](verification/m0-i1-android-sensing.md) | 画面ロック中の位置情報取得と歩数取得が成立するかの検証手順、`flutter_background_geolocation` と `tracelet` の比較結果をまとめています。 |
