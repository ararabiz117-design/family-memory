param(
    [switch]$SkipBuild,
    [ValidateSet('demo', 'staging')]
    [string]$Environment = 'demo',
    [string]$DartDefinesFile = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$flutterRoot = 'C:\Users\arara\develop\flutter-sdk'
$androidSdk = 'C:\Users\arara\develop\android-sdk-36'
$jdkRoot = 'C:\Users\arara\develop\jdk17\jdk-17.0.20+8'

if (-not (Test-Path -LiteralPath (Join-Path $flutterRoot 'bin\flutter.bat'))) {
    throw 'Configured Flutter SDK was not found.'
}

$buildArgs = @('--dart-define=APP_ENV=demo')
if ($Environment -eq 'staging') {
    if ([string]::IsNullOrWhiteSpace($DartDefinesFile) -or -not (Test-Path -LiteralPath $DartDefinesFile)) {
        throw 'staging requires a Git-excluded -DartDefinesFile.'
    }
    $defines = Get-Content -LiteralPath $DartDefinesFile -Raw | ConvertFrom-Json
    $apiUri = $null
    if ($defines.APP_ENV -ne 'staging' -or
        -not [Uri]::TryCreate([string]$defines.CLOUDFLARE_API_URL, [UriKind]::Absolute, [ref]$apiUri) -or
        $apiUri.Scheme -ne 'https' -or -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
        $apiUri.Host.EndsWith('.supabase.co')) {
        throw 'staging requires a Cloudflare HTTPS API URL.'
    }
    $buildArgs = @("--dart-define-from-file=$DartDefinesFile")
}

$env:JAVA_HOME = $jdkRoot
$env:ANDROID_SDK_ROOT = $androidSdk
$env:Path = "$jdkRoot\bin;$androidSdk\platform-tools;$flutterRoot\bin;$env:Path"

Push-Location $projectRoot
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    $formatTargets = @('lib', 'test')
    if (Test-Path -LiteralPath 'integration_test') { $formatTargets += 'integration_test' }
    dart format --output=none --set-exit-if-changed @formatTargets
    if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed.' }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }

    $suspicious = rg -n --hidden --glob '!build/**' --glob '!.dart_tool/**' `
        '(SUPABASE_SERVICE_ROLE_KEY\s*=\s*\S+|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|eyJ[a-zA-Z0-9_-]{20,}\.)' .
    if ($LASTEXITCODE -eq 0) {
        throw "A possible secret was found:`n$suspicious"
    }
    if ($LASTEXITCODE -gt 1) {
        throw 'Secret scan failed to run.'
    }

    if (-not $SkipBuild) {
        flutter build web --release @buildArgs
        if ($LASTEXITCODE -ne 0) { throw 'Web build failed.' }
        flutter build apk --release @buildArgs
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    }
}
finally {
    Pop-Location
}
