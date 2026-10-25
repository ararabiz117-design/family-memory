# 家族の記憶 技術選定と再実装方針

更新: 2026-10-26。選定・ローカル実装と、実サービスの設定・配備・実機検証は別工程として記録する。

## 残す構成・変更する構成

| 選定 | 理由 | 代償・確認事項 |
| --- | --- | --- |
| Flutter / Dartを継続 | 家系図・人物・法事・年間ガイド・画像編集の既存UIとモデルを利用し、Android優先でiOS/Webを同一コードから構築する。大規模な全面書換えによる機能欠落を抑える。 | iOSはmacOS/Xcodeでのビルド・実機確認が必要。Webのアクセシビリティや描画性能は別に確認する。 |
| Cloudflare Workers / TypeScript | ユーザー指定のCloudflareへAPIと認証をまとめる。サーバー側で型と入力検証を行い、ブラウザやアプリへDB秘密情報を配らない。 | サーバーAPIの家族別権限をすべて実装する。TypeScriptの型だけでは外部入力を信用しない。 |
| D1 / SQLite | 人物、家族、関係、予定、費用、招待など関係のある情報にSQLと索引を使える。WorkersのDB bindingで接続できる。 | Supabase PostgreSQLのRLSやRPCは移植されない。family_idとmembershipの検証、更新version、複数操作の整合性が必要。無料枠の上限を監視する。 |
| 非公開R2 | 写真のバイナリを家族データのDBと分離し、写真量の増加へ対応する。公開バケットを作らず、認証済みWorkerを通して配信する。 | R2のキーを知っているだけで閲覧できる設計にしない。家族所属、対象人物/行事、権限の確認が必要。 |
| Google OAuth/OIDCのみ | 毎回メールコードを入力する負担をなくし、既存のGoogleアカウントを利用する。Googleの認証画面をシステムブラウザで開く。 | Googleアカウントが必要。IDトークンのissuer/audience/nonce/有効期限を検証し、メール文字列だけを本人識別の根拠にしない。 |
| OAuthのPKCE・state・nonceとjose | 標準プロトコルを使い、鍵取得と署名検証に監査・更新が行われるライブラリjoseを使う。Googleのsubを識別子とする。 | 独自の暗号方式は作らない。ブラウザ/モバイルごとの戻り先を登録し、許可したURLだけへ戻す。秘密値はWorkers Secretsへ保存する。 |
| Workers AI | ユーザー指定。案内状OCRテキストの候補整理と、一般的な準備案内に限定し、既存の記録の自動収集・自動変更をしない。 | AI出力は誤り得る。実行前に送信する文字列を見せ、操作ごとに明示実行する。DB全体や人物写真を裏で送らない。費用や利用上限は確認する。 |
| AI初期モデル llama-3.3-70b-instruct-fp8-fast | Workers AIのJSON Mode対応モデルとして公開されている。候補の構造化に使い、応答をサーバーで再検証する。モデル名は環境設定で更新可能にする。 | 日本語の実用精度は架空の案内状で別途評価する。JSON Modeも必ず成功するとは限らず、失敗時は手入力へ戻す。 |
| 日本語OCRは端末のML Kit | すでにあるAndroid/iOSの端末内OCRを活用し、写真自体をAIへ送る必要を減らす。AIには確認したテキストだけ送れる。 | Webは手入力と画像添付に対応。Webで同じOCRが使えるとは表示しない。 |
| 画像は端末で縮小しサーバーで再検査 | 端末で向き補正・切抜き・最大1600pxへの縮小、JPEG圧縮を行い転送量を削減。サーバーはmagic/MIME/サイズ/構造を検証し、EXIF・位置情報・コメント等を除去する。 | サーバーの構造検査は完全な画像デコーダではない。JPEG/PNGだけ受理、上限5MB・4096px・1600万画素。SVG/HEIC/WebP等は端末で変換して送信する。画像を回転する前にEXIFを削除すると向きが崩れるため、端末で向きを確定する。 |
| 白を基調としたLiquid Glass表現 | 基本画面は維持し、透過白・やわらかい背景ぼかし・細い境界・控えめな陰影で統一する。利用者の入力情報と操作を中心にして、宣伝用のキャッチコピーは置かない。 | コントラストを下げ過ぎない。低性能端末でぼかし範囲を抑え、文字200%でも操作可能にする。Apple純正UIの完全再現を意味しない。 |
| スケルトンと段階的アニメーション | 一覧/詳細/画像/認証後のデータ待機を画面構造に沿ったスケルトンで表現し、画面遷移・カード・展開に短い動きを入れる。 | 読込み完了時に内容が大きく跳ねない。エラーはスケルトンを終えて再試行を表示。端末の動きを減らす設定に従い、点滅や無限の装飾アニメーションを抑える。 |
| 広告SDKなし | 初版では家族の機微な記録を外部の広告・分析SDKへ送らず、最初の公開と実利用の確認を優先する。 | 広告・課金は今回導入しない。収益化を始める際には利用者への説明とストア申告・プライバシー文書を更新する。 |
| GitHubへソースコード公開 | 履歴管理・レビュー・再現可能なビルドの入口を用意する。公開前に秘密値・画像・データベース・個人情報・署名鍵・既存の配布物を除外する。 | GitHub公開とGoogle Play公開は別。利用者のデータはコードの公開対象ではない。CIは架空fixtureで検証する。 |

## AIにできること・確定しないこと

`extractInvitation` は開催日時・題名・会場の候補と不明点を返す。候補は確認画面を経て通常の予定登録へ渡す。AI関数にはDB/R2/メール等の操作権限を渡さない。`answerGuide` は一般的な準備と寺院/主催者に確認する点を返す。宗派、薄墨の扱い、服装、金額を全国一律の決まりとして提示しない。個別の金融・税務・法律判断は行わない。モデルの生成した根拠不明のリンクは出典として扱わない。

実行には `consent: true` が必須。入力は抽出6000文字、ガイド1200文字まで。応答のキー、型、長さ、実在する日付、時刻を再検証する。レスポンスにも確認が必要である旨を必ず加える。これらは誤回答を完全に防ぐ保証ではなく、候補を安全に確認するための制約。

## 本番設定の順序

1. 個人用Cloudflareアカウントを確認し、専用Worker、D1、R2を新規作成する。会社CareConnectのアカウント・リソースを利用しない。
2. R2のr2.devとカスタム公開ドメインを無効のまま保つ。D1/R2/AIをWorkerにbindingする。
3. GoogleのOAuth同意画面、正規のcallback URL、Web origin、Android/iOSの識別子を設定する。joseで署名を検証する。秘密値は`.dev.vars`（ローカル・Git除外）とWorkers Secrets（本番）で設定する。
4. 匿名fixtureで別家族アクセス拒否、viewer更新拒否、招待期限、競合、添付、削除、出力を確認する。AI実呼出しは確認した架空文字列のみで評価する。
5. Flutterの接続先とログインを切替える。Android実機、Web、iOS実機は各々結果を残す。Supabaseデータ移行はバックアップと件数・関連照合を別途行う。
6. 依存関係・ライセンス・秘密検査を経てコードをGitHubへ公開。ストア提出は署名したAAB、審査用アクセス方法、削除URL、データセーフティ等を用意する。

## 公式資料（2026-10-26確認）

- Flutter対応プラットフォーム: https://docs.flutter.dev/platform-integration
- Workers: https://developers.cloudflare.com/workers/
- D1: https://developers.cloudflare.com/d1/
- R2非公開/公開設定: https://developers.cloudflare.com/r2/buckets/public-buckets/
- Workers AI binding: https://developers.cloudflare.com/workers-ai/configuration/bindings/
- 初期AIモデル: https://developers.cloudflare.com/workers-ai/models/llama-3.3-70b-instruct-fp8-fast/
- JSON Modeと制約: https://developers.cloudflare.com/workers-ai/features/json-mode/
- Workers AIデータの扱い: https://developers.cloudflare.com/workers-ai/platform/data-usage/
- Google OIDC: https://developers.google.com/identity/openid-connect/openid-connect
- OAuth PKCE: https://www.rfc-editor.org/rfc/rfc7636
- jose: https://github.com/panva/jose

無料枠の金額・上限やAIデータ保持条件は変更され得るため、本番で有効にする時点の公式条件を再確認する。ローカルでのモック試験は実Cloudflareの配備、R2設定、Google同意画面審査、実AI精度の証明にはならない。
