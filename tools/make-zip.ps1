<#
  tools/make-zip.ps1 - 把便携目录压成 zip，**保留 UTF-8 文件名**

  为什么不用 tar.exe：Windows 上的 bsdtar 按当前 ANSI 代码页写文件名，在
  GitHub runner（Windows Server 2025 / 1252）上中文会全部变成问号 ——
  "DSH 便携版.exe" 进包后成了 "DSH ???.exe"，"启动 DSH.vbs" 成了 "?? DSH.vbs"，
  同学解压出来就是一堆问号（本机 936 代码页下实测同样会写坏）。
  .NET 的 ZipArchive 直接写 UTF-8 条目名并置好 UTF-8 标志位，
  资源管理器 / 7-Zip / bsdtar 解出来都正常。

  跳过 reparse point（junction），等价于 tar 不跟进链接的行为。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,   # 要打包的目录
    [Parameter(Mandatory = $true)][string]$Zip       # 输出 zip 路径
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$src = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
$leaf = Split-Path -Leaf $src
if (-not (Test-Path -LiteralPath $src -PathType Container)) { throw "找不到目录：$src" }
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
$fs = [IO.File]::Open($Zip, [IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
$count = 0
$skipped = 0
try {
    foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File -Force) {
        if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { $skipped++; continue }
        $rel = $f.FullName.Substring($src.Length + 1).Replace('\', '/')
        $entry = $archive.CreateEntry(($leaf + '/' + $rel), [System.IO.Compression.CompressionLevel]::Optimal)
        $out = $entry.Open()
        $in = [IO.File]::OpenRead($f.FullName)
        try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
        $count++
    }
} finally { $archive.Dispose(); $fs.Dispose() }
if ($skipped) { Write-Host ("  跳过 {0} 个 reparse point（链接）" -f $skipped) }
Write-Host ("  打包 {0} 个文件 -> {1}（{2:N0} MB）" -f $count, $Zip, ((Get-Item -LiteralPath $Zip).Length / 1MB))
exit 0
