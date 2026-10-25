# 家族の記憶

家系図、人物、場所、法要・贈答の記録を家族で共有するFlutterアプリです。

## 構成

- Flutter 3.47.4 / Dart 3.13: Android、iOS、Webで画面とデータモデルを共用。
- Cloudflare Workers: Google認証、家族単位の権限判定、API。
- Cloudflare D1: 人物・関係・場所・行事・招待・変更履歴。
- 非公開Cloudflare R2: 端末側で圧縮・EXIF除去した写真。
- Workers AI: 送信内容を確認し、同意した場合だけ案内状の整理や一般的な案内に使用。

認証はGoogleのみです。WebはHttpOnly Cookie、Android/iOSは暗号化された端末ストレージのセッションを使います。既存のSupabase実装・SQLは移行前の資料として残していますが、現行の `main.dart` は接続しません。

## デモを動かす

```sh
flutter pub get
flutter run -d chrome --dart-define=APP_ENV=demo
```

デモは架空データによる画面確認です。Googleログイン、家族への共有、R2保存、Workers AIの実接続を証明するものではありません。

## Cloudflare版をローカルで動かす

Node.js 24とpnpm 11.25.0を用意し、次のコマンドを別ターミナルで実行します。

```sh
cd cloudflare
pnpm install --frozen-lockfile
pnpm run db:local
pnpm run dev
```

```sh
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8765 --dart-define=APP_ENV=staging --dart-define=CLOUDFLARE_API_URL=http://127.0.0.1:8787
```

Google OAuthを使うには、Workers側のGoogleクライアント設定と許可済みリダイレクトURLが必要です。秘密値は `cloudflare/.dev.vars`（ローカル）またはWrangler secrets（配備先）で管理し、Gitへ登録しません。設定項目は `cloudflare/.dev.vars.example` と `cloudflare/wrangler.jsonc` を参照してください。Workers AIは既定で無効です。実際の配備・データ移行・ストア提出の完了状態は、作業記録と配備先で確認してください。

## 検証とビルド

```sh
flutter analyze
flutter test
flutter build web --release --dart-define=APP_ENV=demo
cd cloudflare
pnpm run check
pnpm test
pnpm run build
```

`pnpm run build` はWorkersのドライランです。公開しません。GitHub Actionsも解析、テスト、デモWeb/Androidビルド、Workersドライランまでを実行します。

実接続のアプリは `APP_ENV=staging` または `production` と `CLOUDFLARE_API_URL` を指定します。Web本番版はアプリとAPIを同一オリジンで配信します。端末用Googleログインの戻り先は `familymemory://login-callback/` です。

署名付きAndroid App Bundleは `tool/build_android_play_aab.ps1 -DartDefinesFile <Git管理外のJSONファイル>` を使用します。JSONには `APP_ENV=production` とHTTPSの `CLOUDFLARE_API_URL` を設定します。アップロード鍵はリポジトリ外に保管し、DPAPIによる保護を維持します。ビルドとGoogle Playへの提出は別の作業です。

## 文書とデータ保護

- `docs/CLOUDFLARE_MIGRATION.md`: 移行構成。
- `docs/RELEASE_CHECKLIST.md`: 公開前確認。Supabase固有の旧記載はCloudflare版の実検証結果と区別してください。
- `docs/FICTIONAL_DATA_POLICY.md`: 開発・テスト用の架空データ規約。
- `docs/PRIVACY_POLICY_DRAFT.md` / `docs/TERMS_DRAFT.md`: 公開前に確認する草案。

家族ごとの権限はサーバーで確認します。氏名・住所・戒名・金額・写真・連絡先・トークンをログに出さず、別家族へのアクセス拒否、同時更新、招待、削除、バックアップ復元を実環境でも確認してから公開してください。
