# 法要案内状の取り込み（ローカル実装メモ）

## 今回の実装

- Android / iOSでカメラ撮影または写真選択。日本語OCRはGoogle ML Kitを端末上で実行し、読み取った全文を送信・保存しない。
- OCR候補から日付、時刻、ラベル付き会場を抽出する。読めない項目は空欄のままにし、利用者が案内状と照合して確認チェックを付けるまで予定を保存しない。
- 保存するのは予定日、イベント名、対象人物、時刻・会場・任意メモ。時刻・自由入力の会場は現行DBに専用列がないため、イベントの要約メモに保存する。日付は共有予定として既存の`date`列へ保存する。
- 家族版では案内状画像をイベント添付として既存の画像処理に渡す。位置情報等を除去・圧縮してからアップロードする。デモでは画像を保存しない。
- 予定日が今日から7日後までの確定予定をアプリ上部の通知アイコンに件数表示する。端末通知（30日前・7日前）は既存設定を使用する。Webは画面内バッジのみ。
- 法要マナーTIPSを「年のそなえ」に追加。金額・服装・墨色は一律ルールとして断定せず、施主・寺院・案内状の指示を優先する。

## 制約・確認事項

- OCRは候補生成であり、手書き・不鮮明・旧字体・レイアウトによって誤読または未検出が起きる。自動確定しない。
- iOSで当該OCRを利用するにはML Kit要件に合わせて最小対応をiOS 15.5へ上げる。今回Windows環境でiOS/Xcode実機ビルドは未検証。
- OCRの日本語対応にはAndroidのJapanese text-recognition依存とiOS CocoaPodsのJapanese podが必要。
- 現行の共有DBは日時ではなく日付だけを保持する。時刻を検索・通知・カレンダー連携で扱うには別途スキーマ/RPC変更が必要。今回DBは変更していない。
- 画像をイベントへ添付する処理は既存のSupabase Storage経路を利用する。今回はローカルコードの変更のみで、SupabaseへのSQL実行・データ変更・配備はしていない。

## 主な参考先

- Google ML Kit Flutter package: https://pub.dev/packages/google_mlkit_text_recognition
- ML Kit Flutter API / 対応OS・日本語設定: https://pub.dev/documentation/google_mlkit_text_recognition/latest/index.html
- 薄墨の扱い（葬祭ディレクター解説）: https://nakamoto.jp/questions-from-customers/kouden_usuzumi/
- お布施（浄土真宗本願寺派 徳正寺 FAQ）: https://www.tokushoji.jp/faq
- 服装（興正寺 FAQ）: https://www.koushoji.or.jp/faq/faq-31/

## 検証

- `flutter test`
- `dart analyze lib test`
- `flutter build web --release`
- Android debug APKビルド成功。初回に既存Gradle署名ガードがdebug taskも拒否する問題を見つけ、release artifact taskのときだけPlay upload keyを要求するよう局所修正した。日本語パスのJNI出力検出で失敗したため、一時的な英数字ジャンクション経由でビルドし、APK生成を確認。
- Windows上でiOS/Xcode実機ビルドは実施していない。

## 最新の保存処理差分（2026-10-24）

- 案内状から新規予定を作る際、DBが発行したイベントIDを受け取ってから写真添付へ渡すよう修正。既存の`save_event_v1`は`id: null`で新規作成し、作成したIDをJSONで返す実装であることをSQLで確認した。
- 予定保存・写真添付・通知同期の失敗を個別に扱い、予定保存に失敗した場合は後続へ進まない。
- この差分適用後は、当該シェルにFlutter/Dart実行ファイルが見つからず、テスト・解析・Web/Androidビルドを再実行できていない。上記の成功記録はこの最新差分より前のソースに対するもの。再検証後に更新する。
