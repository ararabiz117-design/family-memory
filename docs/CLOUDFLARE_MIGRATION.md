# Cloudflare 移行方針・実装状況（ローカル実装・未配備）

更新日: 2026-10-26

## 2026-10-26の実装

`cloudflare/src/`にWorkers API、D1 schema、非公開R2処理、Google OAuth/OIDC（state/nonce/PKCE/jose）、ハッシュ化したセッション、一回限りのログインチケット、招待・権限・version競合保護、削除猶予・Cron、Workers AIを実装した。Flutterの通常起動はCloudflare adapterへ変更し、Googleのみのログインを使用する。旧Supabaseコードは移行元/ロールバック資料として保持する。

認証ライブラリ候補のBetter Authは今回採用せず、Google標準OAuth/OIDCとjose署名検証に絞った。Webは同一オリジンのHttpOnly Cookie、Android/iOSは暗号化ストレージのセッショントークンを使用する。詳細と選定理由は`TECHNOLOGY_CHOICES.md`を参照する。

D1のドメインデータは、family/kind/id/versionをSQLで索引化し、項目は検証済みJSONとして保持する。ユーザー/会員/招待/セッション/画像/削除キューは専用表に分ける。Postgresの20表を機械的に転記する方式ではない。DBへの公開クエリ経路は作らず、全操作をWorkerで認可する。

公開環境への配備、実Google認証、実AIの精度、既存Supabaseデータの移行はまだ未検証。ローカルの試験結果は`IMPLEMENTATION_STATUS.md`へ記録する。

## 決定

利用者の希望により、新しい本番バックエンドはCloudflareを前提に設計する。既存のSupabase専用コード・`supabase/` migrations・stagingプロジェクトは、移行完了とデータ照合が終わるまで変更・削除しない。現時点でCloudflareアカウント、リソース、Secrets、実データは操作しない。

## 推奨構成

- Flutter Web / Android / iOS → HTTPS API（Cloudflare Workers）→ D1 / R2。FlutterからD1・R2へ直接アクセスさせない。
- D1: 家族・メンバー・人物・関係・場所・行事・参加者・費用・贈答・添付メタデータ・操作履歴・削除要求を保存する。
- R2 Standard: 顔写真、墓所写真、案内状等。公開バケットにせず、Workerが毎回ログインと家族所属を確認して配信する。アップロードも短時間・単一オブジェクトに限定した認可済み経路にする。
- 認証: Google標準OAuth/OIDC + joseを採用。Webとモバイルで認可コード・PKCE・一回限りチケットを使い、Bearer API認証とCookieを分ける。永続化・ログアウト・失効の実機テストは別途必要。Better Authは初期候補だったが未採用。
- 定期処理: Cloudflare Workers Cron等で、本人確認後の削除猶予・添付孤児掃除を処理する。Cron資格情報をクライアントへ含めない。
- 画像は現行の端末内リサイズ・EXIF除去を維持し、WorkerでもMIME、実サイズ、対象Family、所有関係を検証する。

## Supabaseとの重要な違い

SupabaseのPostgres RLSはD1には存在しない。よって全データAPIで、認証済みユーザーから有効な`family_members`をサーバー側で確定し、SQL条件を必ず`family_id`付きにし、操作ごとに`owner` / `editor` / `viewer`を再検証する。リクエストが送った`family_id`だけで認可しない。viewer書込、別家族ID、期限切れ/再利用招待、version競合、画像の越境取得をAPI統合試験で拒否できることがリリース条件。

D1はSQLite互換でPostgres RPC/enum/RLSをそのまま移植できない。SQLite制約・トランザクション(batch)・認証スキーマを別管理し、各機能をAPIルートに移す。無料枠にもDBサイズ・行読取/書込・R2操作回数の上限があるため無停止を保証しない。料金・適用条件は本番前に公式料金を再確認する。

## 段階移行

1. Cloudflare Worker/D1/R2のローカル構成、schema、fake identityでのAPIテストを追加。
2. Google OAuth/OIDCとjoseで認証を実装し、FlutterのWeb／Android／iOSで各々セッション・ログアウト・失効を確認。
3. `FamilyRepository` の契約に沿うCloudflare repositoryを追加し、家族・人物・関係・場所・行事・添付・招待・削除・出力のAPI機能を段階移植。
4. 既存Supabase実装を使ったテストと同じ脅威モデルのCloudflare API負試験を通す。架空データだけで一通りの家族共有E2Eを行う。
5. owner承認後、Supabaseを読み取り専用にしてエクスポートし、D1/R2へ移行。件数、ID参照、画像ハッシュ、アクセス権を照合し、復旧手順を確認。
6. 別個人Cloudflare環境へのstaging配備は、その環境・費用・Secrets・Google OAuth redirectを確認してから行う。本番切替、Supabase停止/削除は別の明示承認後のみ。

## 完了ゲート

- unauthenticated/別家族/viewerの権限負試験、version競合、招待期限/再利用/取消、R2の非公開確認が成功。
- 母・子など複数の架空ログインで同一家族の共有編集が成功し、他家族の情報は0件または403。
- account/family削除、データ出力、R2添付削除、セッション失効、バックアップ/復元のテストを通過。
- Android・iOS・Web実機相当E2Eが成功。Supabaseに残るデータとの整合性を照合し、旧環境へ戻す手順を記録。

## 公式参照（2026-10-24確認）

- D1: https://developers.cloudflare.com/d1/
- D1料金: https://developers.cloudflare.com/d1/platform/pricing/
- D1制限: https://developers.cloudflare.com/d1/platform/limits/
- D1データ保護: https://developers.cloudflare.com/d1/reference/data-security/
- R2料金: https://developers.cloudflare.com/r2/pricing/
- R2署名付きURL: https://developers.cloudflare.com/r2/api/s3/presigned-urls/
- Better Auth Google ID token / platform client IDs: https://better-auth.com/docs/authentication/google
- Better Auth D1: https://better-auth.com/blog/1-5
- Better Auth Bearer plugin: https://better-auth.com/docs/plugins/bearer
