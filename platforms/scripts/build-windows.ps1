param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipSigning
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()

Write-Host "==> Building NexoLLM $Version for Windows 10/11 ($Configuration)..."

Push-Location (Join-Path $RepoRoot "platforms")
try {
    cargo test -p nexollm-core
    $CargoFlag = if ($Configuration -eq "Release") { "--release" } else { "" }
    cargo build --workspace $CargoFlag
} finally {
    Pop-Location
}

Push-Location (Join-Path $RepoRoot "platforms\ui")
try {
    if (Test-Path "package.json") {
        npm ci
        npm run build
    }
} finally {
    Pop-Location
}

$OutDir = Join-Path $RepoRoot "dist\windows"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$BinDir = if ($Configuration -eq "Release") { "release" } else { "debug" }
$ExeSrc = Join-Path $RepoRoot "platforms\target\$BinDir\nexollm-desktop.exe"
$ExeDst = Join-Path $OutDir "NexoLLM-$Version-windows-x64.exe"

if (Test-Path $ExeSrc) {
    Copy-Item $ExeSrc $ExeDst -Force
    $Hash = (Get-FileHash -Algorithm SHA256 $ExeDst).Hash.ToLowerInvariant()
    "$Hash  $(Split-Path $ExeDst -Leaf)" | Set-Content (Join-Path $OutDir "SHA256SUMS.txt")
    Write-Host "Built $ExeDst (SHA-256: $Hash)"
    Write-Host "Sign release payload 'NexoLLM-release-v1:$Version`:$Hash' with the maintainer Ed25519 key to emit .sig."
}
