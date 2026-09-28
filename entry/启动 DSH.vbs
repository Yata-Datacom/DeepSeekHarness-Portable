' ============================================================
'  DSH 便携版 — 静默启动器（无黑框闪现，推荐双击这个）
'  直接双击本文件即可。
' ============================================================
Option Explicit
Dim fso, shell, here, ps, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
ps = here & "\launcher\launcher.ps1"

If Not fso.FileExists(ps) Then
    MsgBox "找不到 launcher\launcher.ps1，请确认整个文件夹已完整解压。", 16, "DSH 便携版"
    WScript.Quit 1
End If

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & ps & """"
' 0 = 隐藏窗口；False = 不等待
shell.Run cmd, 0, False
