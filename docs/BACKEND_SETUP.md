# Backend setup（家族限定β）

この文書は、`supabase/` のローカル検証と、承認後に行うstaging接続の手順です。実在人物の情報・実メールアドレス・secretをソース、Issue、AIプロンプト、ログへ入れないでください。

## 現在の実装範囲

- 主要20表、enum、UUID、UTC日時、円整数、不完全日付、`version`、soft delete
- owner / editor / viewer、1ユーザー1 active family、最後のowner保護
- family作成、招待先メールに結び付けた24時間招待、accept、owner承認、招待取消、role変更RPC
- 業務表RLS、別family遮断、private Storage bucketとpath policy
- 同一family参照検証、親子循環拒否、値を複製しないactivity log
- 架空seed、代表的なRLS負テスト
- 招待作成・accept・承認Edge Function
- account削除・家族全削除の30日保留キューとservice-role purge worker
- Storage orphan cleanupとowner限定JSON/CSVテキスト出力

## ローカル適用順

前提はDocker DesktopとSupabase CLIです。プロジェクトルートで実行します。

```powershell
supabase start
supabase db reset
supabase test db supabase/tests/001_rls.sql
supabase test db supabase/tests/002_schema_security.sql
supabase test db supabase/tests/003_write_rpcs.sql
supabase test db supabase/tests/004_private_attachments.sql
supabase test db supabase/tests/005_lifecycle_security.sql
supabase test db supabase/tests/006_place_writes.sql
supabase functions serve --env-file supabase/.env.local
```

`db reset` はlocal DBへ番号順migrationを適用し、その後`supabase/seed.sql`を読み込みます。失敗時は次工程へ進まず、最初のSQLエラーを修正します。Dashboardでschemaを手編集しません。

## Edge Function環境変数

ローカルだけの `supabase/.env.local` に次を設定します。このファイルはGitへ追加しません。

```text
SUPABASE_URL=
SUPABASE_ANON_KEY=
INVITE_APP_LINK_BASE=familymemory://invite
SUPABASE_SERVICE_ROLE_KEY=
LIFECYCLE_WORKER_SECRET=
```

Functionは利用者JWTをそのままSupabaseへ渡し、DB RPCがowner/本人を再検証します。`SUPABASE_SERVICE_ROLE_KEY`と`LIFECYCLE_WORKER_SECRET`は`lifecycle-worker`だけが使用し、Flutter/Webへ入れません。tokenとshort codeはFunction内だけで生成・返却し、DBにはSHA-256だけを保存します。ログへtoken、OTP、メール、人物名、Storage pathを出しません。

削除依頼後は対象へのアクセスを即時停止し、30日後に`lifecycle-worker`が物理削除します。唯一のownerは、owner移譲か家族全削除の依頼完了までaccount削除できません。workerはSupabase Cronなどから1日1回以上、`x-lifecycle-worker-secret` headerを付けてPOSTします。未登録のStorage objectは24時間、soft delete済み添付は30日経過するまで物理削除しません。

招待作成Functionには `familyId`、`invitedEmail`、`role` を渡します。メールアドレスは小文字化してSHA-256化し、平文をDBへ保存しません。受諾時はログイン中JWTのメールと照合し、受諾者の表示名をowner承認画面用のsnapshotとして保存します。

## staging / production

Tokyo stagingプロジェクトの作成、Link、remote migration、custom SMTP、本番メール送信は、所有者の明示承認後だけ行います。承認後はstagingに架空データだけを投入します。

```powershell
supabase link --project-ref <承認済みstaging-ref>
supabase db push --dry-run
supabase db push
supabase functions deploy create-family-invite
supabase functions deploy accept-family-invite
supabase functions deploy approve-family-member
supabase functions deploy request-account-deletion
supabase functions deploy request-family-deletion
supabase functions deploy export-family-data
supabase functions deploy lifecycle-worker --no-verify-jwt
```

productionは別project、Tokyo Pro、custom SMTP、backup/restore検証、法務・実機・ストア申告確認が完了するまで作成・接続しません。publishable key以外をFlutter/Webへ入れません。

## RLS確認

`001_rls.sql`はowner、editor、viewer、別family、anonを切り替え、代表的な読込・書込・version・Storage非公開を検証します。公開判定前には技術設計17章の全ケースへ拡張し、最低限以下もintegration testで確認します。

- 全業務表の別family 0件 / 403
- viewerの全表書込拒否、editorの管理操作拒否
- 期限切れ・取消・二重accept・同時承認
- Storageのlist/read/upload/delete越境拒否とsigned URL失効
- `id AND family_id AND version`付き更新の競合
- account / family削除とStorage purge

## dedicated stagingで確認済み

- `family-memory-staging`（Tokyo）では、初期schemaの存在を確認後、migration 002〜005を適用済みです（2026-09-14）。
- 読み取り検証で、主要20表がRLS有効、`family-private` Storage bucketが非公開であることを確認しました。
- attachmentのmagic bytes/容量/解像度検査、EXIF等除去、immutable path、signed URLのFlutter実装とWidget/Unit試験は完了しました。

## 未検証・所有者作業

- 実JWTと3つの管理可能なメールアカウントを使うOTP/招待/承認/権限E2Eは未検証です。
- pgTAP 6スイート、Edge Functions 6本の`family-memory-staging`へのデプロイ、実行は未検証です。
- 招待acceptの「IP＋userで5回/15分」はDBだけでは完結しないため、gateway側rate limitが未実装です。
- lifecycle用migrationは適用済みです。`lifecycle-worker`のデプロイ、service role / worker secret登録、Cron、30日後purgeの実行確認は未完了です。
- Auth OTP、custom SMTP、session失効、Realtime、backup/restoreは未検証です。
- private Storageの実ファイルupload/read/list/越境拒否とsigned URL失効は未検証です。

Storageは初版migrationでclientからの上書き・物理削除を許可しません。差替えは新しいimmutable pathへ追加し、旧添付はDB側でsoft deleteします。物理削除は監査付きowner専用workerを実装・検証してから追加します。

以上の未確認が残る間は「一般公開可能」と表示しません。家族限定βでも、実データ投入前にlocal→承認済みstagingの順でテストを通します。
