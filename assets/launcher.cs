//  DSH 便携版 — exe 启动入口
//  作用：双击本 exe → 静默调用 launcher\launcher.ps1（WinForms 图形启动器）
//  编译：csc /target:winexe /win32icon:assets\dsh-whale.ico /out:"DSH 便携版.exe" launcher.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

class DshPortableLauncher
{
    [STAThread]
    static void Main(string[] args)
    {
        string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string ps1 = Path.Combine(dir, "launcher\\launcher.ps1");

        if (!File.Exists(ps1))
        {
            MessageBox.Show(
                "找不到 launcher\\launcher.ps1。\n\n请确认整个文件夹已完整解压（不要只复制 exe 单个文件）。",
                "DSH 便携版", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        string psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"";
        if (args != null && args.Length > 0)
        {
            // 透传参数（例如 -Shot out.png）；开关不加引号，含空格的路径才加
            foreach (string a in args)
            {
                if (a.StartsWith("-")) { psArgs += " " + a; }
                else if (a.IndexOf(' ') >= 0) { psArgs += " \"" + a + "\""; }
                else { psArgs += " " + a; }
            }
        }

        var psi = new ProcessStartInfo("powershell.exe", psArgs);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;

        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "启动失败：" + ex.Message +
                "\n\n可以改用同目录下的「启动 DSH.vbs」或「start-dsh.cmd」。",
                "DSH 便携版", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
