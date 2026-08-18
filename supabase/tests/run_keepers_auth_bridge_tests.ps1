$ErrorActionPreference = "Stop"

$chromeCandidates = @(
  "C:\Program Files\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $chrome) {
  throw "Chrome or Edge is required to run the auth bridge tests."
}

$testPage = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "keepers_auth_bridge_test.html")).Path
$testUri = [Uri]::new($testPage).AbsoluteUri
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$runDirectory = Join-Path $tempRoot ("keepers-auth-bridge-tests-" + [Guid]::NewGuid())
$stdoutPath = Join-Path $runDirectory "stdout.txt"
$stderrPath = Join-Path $runDirectory "stderr.txt"

New-Item -ItemType Directory -Path $runDirectory | Out-Null

try {
  $arguments = @(
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--allow-file-access-from-files",
    "--user-data-dir=$runDirectory\profile",
    "--virtual-time-budget=1000",
    "--dump-dom",
    $testUri
  )
  $process = Start-Process `
    -FilePath $chrome `
    -ArgumentList $arguments `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
  $rendered = Get-Content -Raw -LiteralPath $stdoutPath

  if ($process.ExitCode -ne 0) {
    Get-Content -Raw -LiteralPath $stderrPath | Write-Output
    throw "Browser test process exited with code $($process.ExitCode)."
  }

  if ($rendered -notmatch "<title>PASS</title>") {
    $rendered | Write-Output
    throw "Auth bridge tests failed."
  }

  $match = [regex]::Match($rendered, "PASS \([0-9]+ tests\)")
  $match.Value | Write-Output
} finally {
  $resolvedRunDirectory = [IO.Path]::GetFullPath($runDirectory)
  if ($resolvedRunDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedRunDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
