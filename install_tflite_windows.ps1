[CmdletBinding()]
param(
  [string]$Url = "https://github.com/am15h/tflite_flutter_plugin/releases/download/v0.5.0/libtensorflowlite_c-win.dll",
  [string]$OutputPath,
  [string]$ExpectedSha256 = "F1A0ABEDF5B2612AB24518577C2FD5C0CE59D2A19277CF6EBD834D215B5A9200",
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $OutputPath = Join-Path $scriptDir "blobs\libtensorflowlite_c-win.dll"
}

$outputDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-ExpectedHash {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Expected
  )

  if (-not $Expected) {
    return $true
  }

  $actual = Get-Sha256 -Path $Path
  if ($actual -ne $Expected.ToUpperInvariant()) {
    Write-Warning "SHA256 mismatch for '$Path'"
    Write-Warning "Expected: $Expected"
    Write-Warning "Actual:   $actual"
    return $false
  }
  return $true
}

if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
  if (Test-ExpectedHash -Path $OutputPath -Expected $ExpectedSha256) {
    Write-Host "TensorFlow Lite DLL already exists and is valid:"
    Write-Host "  $OutputPath"
    exit 0
  }
  Write-Host "Existing DLL failed hash check. Re-downloading..."
}

$tempFile = Join-Path $env:TEMP ("libtensorflowlite_c-win-" + [guid]::NewGuid().ToString("N") + ".dll")
try {
  Write-Host "Downloading TensorFlow Lite Windows DLL..."
  Write-Host "  URL:  $Url"
  Write-Host "  Path: $OutputPath"

  Invoke-WebRequest -Uri $Url -OutFile $tempFile

  if (-not (Test-ExpectedHash -Path $tempFile -Expected $ExpectedSha256)) {
    throw "Downloaded file hash does not match ExpectedSha256."
  }

  Move-Item -LiteralPath $tempFile -Destination $OutputPath -Force
  Write-Host "Installed successfully:"
  Write-Host "  $OutputPath"
}
finally {
  if (Test-Path -LiteralPath $tempFile) {
    Remove-Item -LiteralPath $tempFile -Force
  }
}
