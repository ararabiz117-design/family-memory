# 家族限定β リリースチェックリスト

未確認項目が1つでもあれば配布候補ではありません。ストア提出と実在家族の招待は、別途明示確認を受けてから行います。

## 現在の公開ブロッカー

- [x] `family-memory-staging` へ家族アプリ用スキーマ、RLS、private Storageを適用済み（2026-09-14確認）。既存の介護アプリ用DBは利用・変更しない。
- [x] Android用upload keystoreをリポジトリ外のWindows DPAPI保護領域へ作成し、Play用AABを署名する（2026-09-15）。iOS署名は未着手。
- [x] `flutter analyze` 0 issues（2026-09-15）。

## 製品

- [x] ホーム、家系図、記録、人物の4タブ
- [x] 「誰だっけ？」と「前回どうした？」が各3操作以内
- [x] 人物、関係者、関係、故人、場所、行事、参加者、費用、贈答のCRUD
- [x] 法要候補と確定予定を別管理し、候補だけでは通知しない
- [x] 前回複製で日付、金額、出欠、人数、添付、当日メモを空にする
- [x] soft delete、変更履歴、owner限定JSON/CSV出力
- [ ] 利用者が操作する「ごみ箱・復元」画面は将来の一般公開前に要否を決める

## 認証・安全

- [ ] Google OAuthを主ログインとして構成し、家族の記憶専用Supabaseで初回プロフィール設定までE2E成功
- [ ] メール6桁OTP、1アカウント1家族（実装済み、実メールE2E・専用DB試験未完了）
- [ ] 24時間・1回限りの招待、取消、owner承認（実装済み、3アカウントE2E・専用DB試験未完了）
- [ ] owner/editor/viewerをUI、API、DBで強制（schema/RLSは専用Supabaseへ適用済み、負テスト・E2E未完了）
- [ ] 主要20業務表のRLSと別家族・未認証の負テスト（RLS有効化は確認済み。負テストは未実施）
- [ ] private Storage、短時間signed URL、EXIF除去、5MiB・JPG/PNG検査（コード/DB試験済み、実ファイルE2E未完了）
- [x] 機微情報、招待token、OTP、保存pathをログへ出さない
- [x] 競合時に無言上書きしない
- [x] 通知本文に氏名・行事名・住所・戒名・金額を含めない

## 品質・端末

- [x] `flutter analyze` 0 issues（2026-09-15）
- [x] `flutter test` 24件成功（2026-09-15）
- [ ] Supabase staging pgTAP（専用Supabaseの構成適用済み。試験は未実施）
- [x] 専用Supabase接続設定のAndroid debug APKを生成し、v2署名検証を実施（2026-09-15、実機検証専用）
- [x] Android API 35エミュレータで専用Supabase接続設定のAPKを起動し、ログイン前画面を確認（2026-09-15）。ログイン後のDB操作は未確認。
- [ ] Android実機、iPhone実機、認証必須Webで受入成功
- [x] 320px幅・文字200%でWidget試験成功
- [ ] 依存ライセンス、既知脆弱性、架空データを確認

## 削除・法務・成果物

- [ ] アカウント削除、owner移譲、家族全削除、backup復元を実データで確認
- [ ] DB/Storage/派生ファイルを30日以内に削除できる
- [ ] 運営者名、問い合わせ先、施行日を確定し法務確認
- [ ] Google Play Data safetyとApp Store App Privacyを実装と照合
- [x] 無料βに課金、広告、解析SDKがない
- [ ] Android applicationIdとversionは確定（`jp.familymemory.app` / `0.4.0+4`）。iOS bundle IDと正式Web originは未確定。
- [ ] 署名秘密をGit管理外へ置く
- [ ] APK/AAB、Web buildのSHA-256を専用Supabase接続版で検証記録へ保存
- [ ] 所有者が限定βの対象者と配布方法を最終確認
