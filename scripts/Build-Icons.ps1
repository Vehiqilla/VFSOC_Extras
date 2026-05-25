# =============================================================================
#  VFSOC :: Build-Icons.ps1
# -----------------------------------------------------------------------------
#  Generates branded .ico files for the three desktop shortcuts (and one
#  generic Vehiqilla brand icon). Each icon is a 256x256 PNG-compressed ICO
#  consisting of:
#     1. A rounded-square gradient background unique to that app.
#     2. The Vehiqilla logo (VFSOC-SIEM/public/logo.png) centred on top.
#
#  Output:
#     assets\icons\vehiqilla.ico      (brand-only, no tint - shared / fallback)
#     assets\icons\vfsoc-admin.ico    (deep navy/indigo gradient)
#     assets\icons\vfsoc-main.ico     (teal/cyan gradient)
#     assets\icons\vfsoc-ingestion.ico (amber/orange gradient)
#
#  Re-run any time logo.png changes or you want to refresh the icons.
# =============================================================================

[CmdletBinding()]
param(
    [string]$LogoPath,
    [string]$OutDir
)

. "$PSScriptRoot\lib\Common.ps1"

$extrasRoot   = Get-VfsocRoot
$projectsRoot = Get-VfsocProjectsRoot

if (-not $LogoPath) {
    $LogoPath = Join-Path $projectsRoot 'VFSOC-SIEM\public\logo.png'
}
if (-not $OutDir) {
    $OutDir = Join-Path $extrasRoot 'assets\icons'
}

if (-not (Test-Path $LogoPath)) {
    throw "Logo not found at $LogoPath. Run setup-vfsoc.ps1 first or pass -LogoPath."
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

Add-Type -AssemblyName System.Drawing

function New-VfsocAppIcon {
    param(
        [Parameter(Mandatory)] [string] $LogoPath,
        [Parameter(Mandatory)] [string] $OutPath,
        [Parameter(Mandatory)] [System.Drawing.Color] $TopColor,
        [Parameter(Mandatory)] [System.Drawing.Color] $BottomColor,
        [int] $Size = 256,
        [double] $LogoScale = 0.62,
        [int] $CornerRadius = 40,
        [switch] $NoBackground
    )

    $logo = [System.Drawing.Image]::FromFile($LogoPath)
    $bmp  = New-Object System.Drawing.Bitmap $Size, $Size
    $g    = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    if (-not $NoBackground) {
        # Rounded-rectangle path for the tile background.
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d    = $CornerRadius * 2
        $rect = New-Object System.Drawing.Rectangle 0, 0, $Size, $Size
        $path.AddArc($rect.X,              $rect.Y,                $d, $d, 180, 90)
        $path.AddArc($rect.Right - $d - 1, $rect.Y,                $d, $d, 270, 90)
        $path.AddArc($rect.Right - $d - 1, $rect.Bottom - $d - 1,  $d, $d,   0, 90)
        $path.AddArc($rect.X,              $rect.Bottom - $d - 1,  $d, $d,  90, 90)
        $path.CloseFigure()

        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, $TopColor, $BottomColor, 60.0)
        $g.FillPath($brush, $path)

        # Subtle inner highlight for depth.
        $hiPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, 255, 255, 255)), 2
        $g.DrawPath($hiPen, $path)

        $brush.Dispose(); $hiPen.Dispose(); $path.Dispose()
    }

    # Centre the logo, preserving aspect ratio.
    $logoSize = [int]($Size * $LogoScale)
    $aspect   = $logo.Width / $logo.Height
    if ($aspect -ge 1) {
        $w = $logoSize; $h = [int]($logoSize / $aspect)
    } else {
        $h = $logoSize; $w = [int]($logoSize * $aspect)
    }
    $x = [int](($Size - $w) / 2)
    $y = [int](($Size - $h) / 2)
    $g.DrawImage($logo, $x, $y, $w, $h)

    # Serialise the bitmap as a PNG inside an ICO container (Vista+ format,
    # supported by Windows shortcuts and Explorer at any rendered size).
    $pngStream = New-Object System.IO.MemoryStream
    $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes  = $pngStream.ToArray()

    $ico = New-Object System.IO.MemoryStream
    $bw  = New-Object System.IO.BinaryWriter $ico
    # ICONDIR
    $bw.Write([uint16]0)                       # idReserved
    $bw.Write([uint16]1)                       # idType (1 = ICO)
    $bw.Write([uint16]1)                       # idCount
    # ICONDIRENTRY
    $bw.Write([byte]0)                         # bWidth  (0 = 256)
    $bw.Write([byte]0)                         # bHeight (0 = 256)
    $bw.Write([byte]0)                         # bColorCount
    $bw.Write([byte]0)                         # bReserved
    $bw.Write([uint16]1)                       # wPlanes
    $bw.Write([uint16]32)                      # wBitCount
    $bw.Write([uint32]$pngBytes.Length)        # dwBytesInRes
    $bw.Write([uint32]22)                      # dwImageOffset (6 + 16)
    $bw.Write($pngBytes)

    [System.IO.File]::WriteAllBytes($OutPath, $ico.ToArray())

    $g.Dispose(); $bmp.Dispose(); $logo.Dispose(); $pngStream.Dispose(); $ico.Dispose()
    Write-VfsocOk "Wrote $OutPath ($([math]::Round((Get-Item $OutPath).Length/1KB,1)) KB)"
}

Write-VfsocBanner "Generating Vehiqilla-branded shortcut icons"
Write-Host ("  Source logo : {0}" -f $LogoPath) -ForegroundColor DarkGray
Write-Host ("  Output dir  : {0}" -f $OutDir)   -ForegroundColor DarkGray

# Brand-only Vehiqilla icon (no tint) for any future generic use.
New-VfsocAppIcon -LogoPath $LogoPath `
                 -OutPath  (Join-Path $OutDir 'vehiqilla.ico') `
                 -TopColor    ([System.Drawing.Color]::FromArgb(255, 17, 24, 39)) `
                 -BottomColor ([System.Drawing.Color]::FromArgb(255,  3,  7, 18)) `
                 -LogoScale 0.78

# VFSOC Admin -- deep navy / indigo (security & trust).
New-VfsocAppIcon -LogoPath $LogoPath `
                 -OutPath  (Join-Path $OutDir 'vfsoc-admin.ico') `
                 -TopColor    ([System.Drawing.Color]::FromArgb(255,  37,  99, 235)) `
                 -BottomColor ([System.Drawing.Color]::FromArgb(255,  17,  24,  82))

# VFSOC Main Dashboard -- teal/cyan (analytics & insight).
New-VfsocAppIcon -LogoPath $LogoPath `
                 -OutPath  (Join-Path $OutDir 'vfsoc-main.ico') `
                 -TopColor    ([System.Drawing.Color]::FromArgb(255,  14, 165, 233)) `
                 -BottomColor ([System.Drawing.Color]::FromArgb(255,  15,  82, 100))

# VFSOC Ingestion -- amber/orange (active data flow).
New-VfsocAppIcon -LogoPath $LogoPath `
                 -OutPath  (Join-Path $OutDir 'vfsoc-ingestion.ico') `
                 -TopColor    ([System.Drawing.Color]::FromArgb(255, 249, 115,  22)) `
                 -BottomColor ([System.Drawing.Color]::FromArgb(255, 120,  53,  15))

Write-VfsocBanner "Done"
Write-Host "Icons available under $OutDir" -ForegroundColor White
