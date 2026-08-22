param(
    [string]$AppRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $AppRoot 'assets\brand\keepers-wordmark.png'
$source = [System.Drawing.Bitmap]::FromFile($sourcePath)

# Bounds of the supplied black wordmark inside its white source canvas.
$sourceBounds = [System.Drawing.Rectangle]::new(148, 402, 1221, 319)
$ink = [System.Drawing.Bitmap]::new(
    $sourceBounds.Width,
    $sourceBounds.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)

for ($y = 0; $y -lt $sourceBounds.Height; $y += 1) {
    for ($x = 0; $x -lt $sourceBounds.Width; $x += 1) {
        $pixel = $source.GetPixel($sourceBounds.X + $x, $sourceBounds.Y + $y)
        $luminance = (0.2126 * $pixel.R) + (0.7152 * $pixel.G) + (0.0722 * $pixel.B)
        $alpha = [Math]::Clamp([Math]::Round(255 - $luminance), 0, 255)
        if ($alpha -lt 8) {
            $alpha = 0
        }
        $ink.SetPixel(
            $x,
            $y,
            [System.Drawing.Color]::FromArgb($alpha, 239, 231, 212)
        )
    }
}
$source.Dispose()

function Write-LaunchWordmark {
    param(
        [string]$Path,
        [int]$CanvasWidth,
        [int]$CanvasHeight,
        [int]$InkWidth
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $canvas = [System.Drawing.Bitmap]::new(
        $CanvasWidth,
        $CanvasHeight,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    $inkHeight = [Math]::Round($InkWidth * $ink.Height / $ink.Width)
    $destination = [System.Drawing.Rectangle]::new(
        [Math]::Round(($CanvasWidth - $InkWidth) / 2),
        [Math]::Round(($CanvasHeight - $inkHeight) / 2),
        $InkWidth,
        $inkHeight
    )
    $graphics.DrawImage($ink, $destination)
    $graphics.Dispose()
    $canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
}

# Treat the source as mdpi so Android preserves its logical size when it
# scales the pre-Android 12 launch screen on high-density devices.
Write-LaunchWordmark `
    -Path (Join-Path $AppRoot 'android\app\src\main\res\drawable-mdpi\keepers_launch_wordmark.png') `
    -CanvasWidth 288 `
    -CanvasHeight 288 `
    -InkWidth 168

Write-LaunchWordmark `
    -Path (Join-Path $AppRoot 'assets\brand\keepers-launch-wordmark.png') `
    -CanvasWidth 196 `
    -CanvasHeight 78 `
    -InkWidth 158

$iosRoot = Join-Path $AppRoot 'ios\Runner\Assets.xcassets\LaunchImage.imageset'
Write-LaunchWordmark -Path (Join-Path $iosRoot 'LaunchImage.png') -CanvasWidth 196 -CanvasHeight 78 -InkWidth 158
Write-LaunchWordmark -Path (Join-Path $iosRoot 'LaunchImage@2x.png') -CanvasWidth 392 -CanvasHeight 156 -InkWidth 316
Write-LaunchWordmark -Path (Join-Path $iosRoot 'LaunchImage@3x.png') -CanvasWidth 588 -CanvasHeight 234 -InkWidth 474

$ink.Dispose()
