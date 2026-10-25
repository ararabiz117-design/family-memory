param(
    [string]$Flutter = "C:\Users\arara\develop\flutter-sdk\bin\flutter.bat",
    [ValidateSet("demo", "staging")]
    [string]$Environment = "demo",
    [string]$DartDefinesFile = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not (Test-Path -LiteralPath $Flutter)) {
    throw "Flutter SDK was not found. Pass -Flutter with an absolute path."
}

if ($Environment -eq "staging") {
    if ([string]::IsNullOrWhiteSpace($DartDefinesFile) -or -not (Test-Path -LiteralPath $DartDefinesFile)) {
        throw "staging requires -DartDefinesFile. Do not save that file in the repository."
    }
    $defines = Get-Content -LiteralPath $DartDefinesFile -Raw | ConvertFrom-Json
    $apiUri = $null
    if ($defines.APP_ENV -ne "staging" -or
        -not [Uri]::TryCreate([string]$defines.CLOUDFLARE_API_URL, [UriKind]::Absolute, [ref]$apiUri) -or
        $apiUri.Scheme -ne 'https' -or -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
        $apiUri.Host.EndsWith('.supabase.co')) {
        throw "The staging defines file is incomplete or unsafe."
    }
}

& $Flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$buildArgs = @()
if ($Environment -eq "staging") {
    $buildArgs = @("--dart-define-from-file=$DartDefinesFile")
}

& $Flutter build web --release @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Flutter build apk --release @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Flutter build appbundle --release @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Release checks passed for $Environment."
