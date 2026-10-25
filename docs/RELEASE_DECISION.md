# 公開判定

更新日: 2026-09-14

## 現在の判定

`CODE IMPLEMENTED / STAGING BASELINE VERIFIED / NOT YET DISTRIBUTABLE`

Flutterの主要画面・データ操作・認証導線、専用staging DBのschema/RLS/private Storage、Web buildと単体/Widget試験までを実装した。家族限定βの配布前に、Google OAuth設定、3家族アカウント、実端末、専用署名、外部Function、法務情報の最終ゲートを通す。

## コードで完了したゲート

- 添付の形式・容量検査、EXIF除去、private Storage、signed URL
- 確定予定だけを対象にした端末通知
- account削除、family全削除、30日purge、Storage清掃、owner限定export
- 全表RLS、Storage実操作、競合、招待rate limitの追加試験
- 専用アプリアイコン、ディープリンク、アプリ名、権限宣言
- Web / Android / iPhone向けOAuth戻り先のアプリ実装
- unit/widget test、Web release build

確認済みなのは、`flutter test` 23件成功、Web release build、`family-memory-staging`の20 RLS有効表と非公開Storage bucketである。`flutter analyze` はWindowsパス起因のツールエラーで未完走、GoogleログインE2E、staging pgTAP、Edge Functionsの専用stagingへの配備は未確認である。

## 所有者と実環境で完了させるゲート

- 3つの家族アカウントでログイン、招待、owner承認、owner/editor/viewerを確認
- Android実機、iPhone実機、Web共有PCで受入試験
- 専用release keystore、Apple署名、TestFlight
- custom SMTP、backup/restore、削除workerの実行確認
- lifecycle worker用のservice role / secret登録とCron設定
- 運営者名、問い合わせ先、プライバシーポリシーURLを確定
- Google Play Data safety / App Store App Privacyを実装と照合

上記が終わるまで、実在家族データの投入、一般配布、ストア提出は行わない。現在の0.4.0は「専用DB接続前の検証成果物を含むstaging試験版」であり、公開署名済み製品版ではない。
