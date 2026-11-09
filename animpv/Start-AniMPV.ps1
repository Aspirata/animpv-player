param(
    [string]$MpvPath = $env:ANIMPV_MPV,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Media
)
$ErrorActionPreference = 'Stop'
if (-not $MpvPath) {
    foreach ($candidate in @((Join-Path $PSScriptRoot 'bin/mpv.exe'), (Join-Path $PSScriptRoot 'mpv.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $MpvPath = $candidate; break }
    }
}
if (-not $MpvPath) {
    $command = Get-Command mpv.exe -ErrorAction SilentlyContinue
    if ($command) { $MpvPath = $command.Source }
}
if (-not $MpvPath -or -not (Test-Path -LiteralPath $MpvPath -PathType Leaf)) {
    throw 'mpv was not found. Put a standalone mpv engine in animpv/bin, set ANIMPV_MPV, or pass -MpvPath.'
}
$enginePath = (Resolve-Path -LiteralPath $MpvPath).Path
foreach ($folder in @('state', 'screenshots')) {
    [System.IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot $folder)) | Out-Null
}
& $enginePath "--config-dir=$PSScriptRoot" '--' @Media
if ($LASTEXITCODE) { exit $LASTEXITCODE }
