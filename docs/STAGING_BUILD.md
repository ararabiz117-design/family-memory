# stagingビルド手順

Supabaseのpublishable keyは公開クライアントへ埋め込む用途のキーだが、設定値をソース、コミット、ログ、ドキュメントへ保存しない。`service_role`またはsecret keyは絶対にクライアントへ渡さない。

プロジェクト外の一時JSONを用意する。

```json
{
  "APP_ENV": "staging",
  "SUPABASE_URL": "https://PROJECT_REF.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_REPLACE_ME"
}
```

検証・Web・APK・AABを一括実行する。

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\release_check.ps1 `
  -Environment staging `
  -DartDefinesFile "C:\absolute\path\outside-repository\staging-defines.json"
```

終了後は一時JSONを安全に削除する。成果物にpublishable keyが含まれることはSupabaseのクライアント設計上の前提であり、RLSが実際の防御境界となる。

