[CmdletBinding()]
param(
    [switch]$ResetUploadKey,
    [string]$DartDefinesFile = 'C:\Users\arara\develop\family_memory_release_defines.json'
)

$ErrorActionPreference = 'Stop'

# This script keeps the upload key outside the repository. The metadata file is
# encrypted with Windows DPAPI and can only be read by this Windows account.
$userProfile = [Environment]::GetFolderPath('UserProfile')
if ([string]::IsNullOrWhiteSpace($userProfile)) {
    throw 'Could not resolve the Windows user profile for protected signing material.'
}
$secureRoot = Join-Path $userProfile '.family-memory-release'
$keystorePath = Join-Path $secureRoot 'family-memory-upload.jks'
$secretPath = Join-Path $secureRoot 'family-memory-upload.dpapi'
$alias = 'family-memory-upload'
$flutter = 'C:\Users\arara\develop\flutter-sdk\bin\flutter.bat'
$defines = $DartDefinesFile
$outputDir = Join-Path $PSScriptRoot '..\release\play'

# Validate the active backend before reading or creating signing material.
if (-not (Test-Path -LiteralPath $defines)) {
    throw 'Pass -DartDefinesFile containing APP_ENV=production and CLOUDFLARE_API_URL.'
}
$releaseConfig = Get-Content -LiteralPath $defines -Raw | ConvertFrom-Json
$apiUri = $null
if ($releaseConfig.APP_ENV -ne 'production' -or
    -not [Uri]::TryCreate([string]$releaseConfig.CLOUDFLARE_API_URL, [UriKind]::Absolute, [ref]$apiUri) -or
    $apiUri.Scheme -ne 'https' -or -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
    $apiUri.Host.EndsWith('.supabase.co')) {
    throw 'Play builds require a production Cloudflare HTTPS API URL.'
}

function New-StrongPassword {
    $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%*-_'
    $bytes = New-Object byte[] 36
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

if ($ResetUploadKey) {
    Remove-Item -LiteralPath $keystorePath, $secretPath -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $secureRoot, $outputDir | Out-Null

if ((Test-Path -LiteralPath $keystorePath) -xor (Test-Path -LiteralPath $secretPath)) {
    throw 'Upload key material is incomplete. Restore both protected files or rerun with -ResetUploadKey before a first Play upload.'
}

if (-not (Test-Path -LiteralPath $keystorePath)) {
    $password = New-StrongPassword
    $keytool = if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        'keytool'
    }
    else {
        Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    }
    if ($keytool -ne 'keytool' -and -not (Test-Path -LiteralPath $keytool)) {
        $keytool = 'keytool'
    }
    if ($keytool -eq 'keytool' -and -not (Get-Command keytool -ErrorAction SilentlyContinue)) {
        $flutterJdkKeytool = 'C:\Users\arara\develop\jdk17\jdk-17.0.20+8\bin\keytool.exe'
        if (Test-Path -LiteralPath $flutterJdkKeytool) {
            $keytool = $flutterJdkKeytool
        }
        else {
            throw 'No JDK keytool was found. Configure Flutter with a JDK before creating the Play upload key.'
        }
    }

    & $keytool -genkeypair `
        -keystore $keystorePath `
        -storetype JKS `
        -storepass $password `
        -keypass $password `
        -alias $alias `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname 'CN=Family Memory Upload, OU=Android, O=Family Memory, C=JP' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the Play upload key.' }

    $secret = @{ password = $password; alias = $alias } | ConvertTo-Json -Compress |
        ConvertTo-SecureString -AsPlainText -Force |
        ConvertFrom-SecureString
    Set-Content -LiteralPath $secretPath -Value $secret -NoNewline -Encoding ascii
}

$protected = Get-Content -LiteralPath $secretPath -Raw | ConvertTo-SecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($protected)
try {
    $metadata = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) | ConvertFrom-Json
    $password = $metadata.password
    $alias = $metadata.alias
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$env:FAMILY_MEMORY_ANDROID_STORE_FILE = $keystorePath
$env:FAMILY_MEMORY_ANDROID_STORE_PASSWORD = $password
$env:FAMILY_MEMORY_ANDROID_KEY_ALIAS = $alias
$env:FAMILY_MEMORY_ANDROID_KEY_PASSWORD = $password

Push-Location (Join-Path $PSScriptRoot '..')
try {
    & $flutter build appbundle --release --dart-define-from-file=$defines
    if ($LASTEXITCODE -ne 0) { throw 'Flutter could not build the signed Play AAB.' }

    $aab = Join-Path (Get-Location) 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path -LiteralPath $aab)) { throw 'The signed AAB was not produced.' }
    $version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value
    $destination = Join-Path $outputDir "family-memory-$version-play-upload.aab"
    Copy-Item -LiteralPath $aab -Destination $destination -Force
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash | Set-Content -LiteralPath "$destination.sha256" -NoNewline -Encoding ascii
    Write-Host "Signed AAB: $destination"
}
finally {
    Pop-Location
    Remove-Item Env:FAMILY_MEMORY_ANDROID_STORE_FILE, Env:FAMILY_MEMORY_ANDROID_STORE_PASSWORD, Env:FAMILY_MEMORY_ANDROID_KEY_ALIAS, Env:FAMILY_MEMORY_ANDROID_KEY_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
}
