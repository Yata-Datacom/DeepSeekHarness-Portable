<#
  tools/sign-file.ps1 - 用发布证书给单个文件做 Authenticode 签名（作为子进程调用）

  为什么要单独一个子进程：pwsh 7（.NET Core）下用 EphemeralKeySet 载入私钥后调
  Set-AuthenticodeSignature 会返回 UnknownError，而 Windows PowerShell 5.1
  （.NET Framework）签同一个文件完全正常。密码从环境变量读，不出现在命令行里。
  退出码：0 成功 / 2 找不到 PFX / 3 证书没有私钥 / 4 签名结果不是 Valid
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Pfx = $env:SIGN_PFX_PATH
)
$ErrorActionPreference = 'Stop'
if (-not $Pfx -or -not (Test-Path -LiteralPath $Pfx)) { Write-Error "找不到 PFX：$Pfx"; exit 2 }
$pw = $env:SIGN_PFX_PASSWORD
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $Pfx, $pw, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
if (-not $cert.HasPrivateKey) { Write-Error "证书不带私钥（PFX 或密码不对）：$Pfx"; exit 3 }
$sig = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -HashAlgorithm SHA256
if ($sig.Status -ne 'Valid') { Write-Error "签名结果：$($sig.Status)"; exit 4 }
Write-Host ("  PS {0} 签名成功：{1}" -f $PSVersionTable.PSVersion, (Split-Path $Path -Leaf))
exit 0
