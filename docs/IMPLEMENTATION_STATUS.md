# 家族の記憶 — 実装・検証状態

更新日: 2026-10-26 / 0.5.0+5

## 現在の状態（以下の過去記録より優先）

Flutterの4タブを維持し、白ベースのLiquid Glass UIへ変更。端末の動きを減らす設定に従う画面遷移とカードアニメーション、実際の初期データ・画像・AI待機にスケルトンを追加した。新しい接続版はCloudflare Worker APIを利用し、Google認証だけを提供する。

D1では家族所属とroleをサーバーで確定し、version競合、招待先照合・owner承認、最後のowner保護、削除キューを実装。非公開R2は画像検査・位置情報等のmetadata除去・短時間署名URLを使用する。Workers AIは入力テキストの確認と実行ごとの同意を必須とし、AI候補の自動保存はしない。

旧Supabaseソースは移行・ロールバックの参考として保持し、現在のmainでは起動しない。既存Supabase、会社CareConnect、Expo、WordPressには変更を加えていない。技術選定の理由は`TECHNOLOGY_CHOICES.md`、移行は`CLOUDFLARE_MIGRATION.md`を参照。

### 今回の検証

- Android debug APKビルド成功。`build/app/outputs/flutter-apk/app-debug.apk`は実機検証用で、Play提出用の署名済みAABではない。
- Flutter Web release（架空デモ）ビルド成功。`build/web-preview`を127.0.0.1:8766で確認。
- Cloudflare接続版Web releaseもビルド成功（`build/web-family`）。実Google認証の成功ではない。
- `dart analyze lib test`: No issues found。日本語パスで解析サーバーにURIエラーが出たため、既存ASCII junction経由で実行。
- Flutterテスト39件を一括実行して合格（AI画面、320px幅・文字200%を含む）。
- Worker API/画像/AIテスト19件合格。TypeScript checkとWrangler dry-run bundle成功。
- ローカルWrangler設定にはAI bindingを置かず、AIは無効。実AI bindingは本番用設定だけに置き、ローカル起動でCloudflare認証やリモート呼出しを要求しない。
- 実workerd + ローカルD1のsmoke test合格（認証拒否・家族snapshot・version競合）。実Cloudflareへの配備検証ではない。
- 指定の個人Chromeでスマホ幅のホーム・家系図・記録・法要詳細・人物を実操作。全ボタン・実機の合格を意味しない。
- スマホ幅の家系図で中心人物が画面外になる問題と、配偶者が中心と重なる問題を修正。320px幅の配置回帰テストを追加し、関連Widgetテスト5件合格（既存一括39件とは別）。

### 本番運用・ストア公開の残件

1. 個人Cloudflare環境にWorker/D1/非公開R2を設定し、Google OAuth Client・Workers Secrets・同一origin HTTPS URLを配備。
2. 実Googleログイン、複数家族の招待・共有・権限、実R2、AI実応答、削除・バックアップ復元を確認。
3. Supabaseの保存済みデータがある場合は件数・参照・画像ハッシュを照合して移行。旧DBは削除・停止しない。
4. Android実機のログイン復帰・通知・カメラ、macOS/XcodeでのiOSビルド・実機確認。
5. Play提出用AABの署名、運営者情報、公開プライバシーポリシーと削除URL、Data Safety、審査アクセス、Console所定のテストと申告。

`APP_ENV=demo`（既定）は架空の「青葉家」のメモリ内データであり永続共有・AI送信なし。`staging`/`production`は`CLOUDFLARE_API_URL`が必須で、未設定時にデモへ戻さず安全停止する。

以上の外部ゲートを完了するまで「一般公開可能」「実データ共有の検証完了」と判定しない。

---

## 以下は2026-09-14時点の過去記録（現在の接続設定には使用しない）

内部Context記録: receipt `8cf79ef7-9ca0-45c3-9fa9-850e6d9a1d0f` / applied knowledge IDs `p001-principle-safe-experimentation-v1`, `p001-principle-unique-reader-experience-v1`, `p001-principle-freedom-dignity-ai-dx-v1`

## 現在利用できるもの

- Flutter単一コードベース（Android / iOS / Web）
- ホーム、家系図、記録、人物の固定4タブ
- 淡いピンク・ミント・クリーム色、丸いカード、ハートの家族ロゴを使った親しみやすいライトUI
- 家族の木と3つのハートを表した専用アプリアイコン（Android / iOS / Webへ生成済み）
- 「誰だっけ？」検索と人物詳細
- 「前回どうした？」検索と法要・費用・参加者詳細
- 中心人物を切り替える家系図表示
- 人物・関係者の追加編集、故人・戒名・宗派・場所情報
- 行事の追加編集、法要候補の確認、前回記録の安全な複製
- owner / editor / viewer の画面確認用切替
- 320px幅、文字200%を含むWidgetテスト
- Supabase用の20表、RLS、version競合、soft delete、招待承認、private Storage policyのmigration
- 招待作成・受諾・owner承認のEdge Functionソース
- 架空seedと代表RLSテストSQL
- Googleログインを主導線、メールリンク／確認コードを予備導線とする認証画面
- プロフィール初期設定、家族作成・招待参加・owner承認待ちのFlutter画面
- owner用の招待コード発行、承諾者の表示名確認・承認、招待取消、家族権限変更画面
- Supabaseから家族・人物・場所・行事・費用・参加者を読み込む実Repository
- 人物と行事を関連データごと保存するversion検査付きatomic RPC
- 場所の追加・編集と外部地図起動
- 行事参加者と費用の追加・編集
- 画像の形式・magic bytes・容量・解像度検査、EXIF等のmetadata除去、immutable path、signed URL
- 確定した予定のみを対象とする端末通知とディープリンク
- owner限定JSON/CSV出力、account/family削除予約、30日後purgeの基盤
- Webの30分無操作再ロック

SupabaseのURLとpublishable keyを指定しない通常ビルドは、実在しない「青葉家」のデモモードで動作する。入力内容はアプリ終了時に消え、家族へ共有されない。

`APP_ENV=staging` または `production` では、URLやkeyの不足時に安全停止画面を表示する。設定済みの場合は認証・家族参加フローと実Repositoryを起動し、無言でデモへ戻らない。

共有履歴の直接更新権限はクライアントから外し、version一致を必須にするatomic RPCへ限定した。競合時は再読込を促し、他人の変更を無言で上書きしない。

## 2026-09-09 安全監査で反映した修正

- 招待を平文保存しない招待先メールhashへ結び付け、受諾JWTのメールと照合する。
- owner確認用に受諾者の表示名snapshotを保存する。
- soft delete済み業務データを通常のRLS読込から除外する。
- Storage clientの上書き・物理削除policyを削除し、監査を迂回する改ざんを防ぐ。
- 法要候補列、任意参加者ID、未入力金額をschemaへ反映し、Flutterモデルとの重大な不一致を縮小する。
- publishable keyの設定名をアプリと `.env.example` で統一する。

## 認証導線として実装済みの内容

- Google OAuthをFlutter Web / Android / iPhoneの共通ログイン導線として実装した。
- Webは現在のorigin、Android / iPhoneは `familymemory://login-callback/` へ戻す。
- Webは現在のorigin、Android / iPhoneは `familymemory://login-callback/` へ戻る実装にした。
- リダイレクト先の設定は開発用URLとアプリschemeを想定している。
- Google OAuth providerの家族アプリ専用Supabase環境での有効化・実E2Eは未確認である。Client Secretはリポジトリ、配布文書、ローカル設定ファイルへ保存しない。
- メール送信後の画面は、リンク確認が主で6桁コードはメールに表示された場合だけ使う説明へ修正した。

## 検証済み

- `flutter test`: 23 tests passed（2026-09-14）
- Flutter Web release build: 成功
- Android release-mode APK / AAB build: 過去の検証成果物あり。専用release keystore署名ではない。
- Web 320px表示: ホームと人物検索を目視確認
- secret pattern scan: 実credentialなし
- `family-memory-staging`（Tokyo）へmigration 002〜005を適用。初期schemaを含む主要20表はRLS有効、`family-private` bucketは非公開（2026-09-14）。
- `family-memory-staging`上のpgTAP、Edge Functionsのデプロイ、実Storage操作は未検証。
- 新UI反映後のAndroid demo APK / Web demo ZIP再ビルド: 成功（2026-09-10）
- 新UI反映後の配布物SHA-256を `release/SHA256SUMS-2026-09-10.txt` へ記録
- staging接続版0.3.0のAndroid APK / AAB / Web ZIPビルド: 成功（2026-09-11）
- APKの署名検証: APK Signature Scheme v2で正常。ただし署名者は `Android Debug`のためスト専用
- 0.3.0配布物のSHA-256を `release/SHA256SUMS-0.3.0.txt` へ記録
- Google OAuthの`family-memory-staging`接続での実E2Eは未実施。
- staging接続版0.4.0のAndroid APK / AAB / Web ZIPビルド: 成功（2026-09-12）
- Android API 35エミュレータへ0.4.0 APKをインストールし、ログイン画面の起動を確認
- Androidの `familymemory://login-callback/` intentが `jp.familymemory.app/.MainActivity` へ届くことを確認
- APK署名検証: APK Signature Scheme v2で正常、署名者は `Android Debug`
- AABのJAR署名検証: 成功、署名者は `Android Debug`
- Web ZIPのrootに `index.html` があることを確認
- 0.4.0配布物のSHA-256を `release/SHA256SUMS-0.4.0.txt` へ記録
- `family-memory-staging` 接続設定のAndroid debug APKを再ビルドし、v2署名検証に成功（2026-09-15）。証明書は `Android Debug` のため実機検証専用。詳細は `docs/verification/2026-09-15_android-debug.md`。

`flutter analyze` は日本語を含むWindowsパス環境でツール側の `FormatException` により完走できていない。静的解析の成功扱いにはしない。

## 家族限定の実運用前に必要な外部作業

次は外部環境・秘密情報・実端末を伴うため、ソースだけでは完了判定しない。

1. 3つの管理可能な家族アカウントでGoogleログインまたはメール認証、招待、owner承認、owner/editor/viewerのE2Eを通す。Google OAuthがテスト中の間は各Googleアカウントをテストユーザーへ追加する。
2. 家族のメール予備導線に必要なcustom SMTP、private Storage実操作、端末通知、backup/restoreをstaging実環境で検証する。
3. service roleと新規worker secretをSupabase Secretsへ登録し、`lifecycle-worker`をデプロイしてCronを設定する。これらの値はアプリとリポジトリへ保存しない。
4. Android専用release/upload keystoreを安全に作成・保管し、Play App Signing用に再ビルドする。現在のAPK/AABはdebug key署名のstaging試験用である。
5. Android実機closed test、macOSでiPhone TestFlight、HTTPSのWeb共有PC試験を行う。
6. production Supabase、運営者名、受信確認済み問い合わせ先、プライバシーポリシー、利用規約、ストア申告を確定する。

上記が終わるまでは「一般公開可能」または「実在家族データを安全に共有可能」と表示しない。

## 将来の収益化

課金・広告・有料制限は初版に入れていない。データ所有権や家族共有の安全性を壊さず後からEntitlementを追加する方針は `FUTURE_MONETIZATION.md` に分離した。
