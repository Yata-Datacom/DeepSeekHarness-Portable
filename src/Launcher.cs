//  DSH 便携版 — 图形启动器（C# / WinForms）
//
//  Ported from launcher\launcher.ps1. Only the presentation lives here: every
//  decision (what is installed, is the host safe, how a server starts) is still
//  made by launcher\core.ps1, reached through tools\core-bridge.ps1 as JSON.
//  That keeps one source of truth and lets the UI be compiled ahead of time.
//
//  Build (no SDK needed, the framework compiler that ships with Windows):
//    csc /nologo /target:winexe /win32icon:assets\dsh-whale.ico ^
//        /r:System.Web.Extensions.dll /out:"DSH 便携版.exe" src\Launcher.cs
//  Then SIGN it: Smart App Control blocks a brand-new unsigned binary.
//
//  C# 5 only - the in-box compiler has no newer language features.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

class Launcher
{
    // ---------- bridge ----------
    static string PkgDir;
    static string BridgePath;

    static string BridgeRaw(string action, string extra, string stdinText)
    {
        var psi = new ProcessStartInfo("powershell.exe");
        string a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + BridgePath + "\" -Action " + action;
        if (extra != null && extra.Length > 0) { a += " " + extra; }
        psi.Arguments = a;
        psi.UseShellExecute = false;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardInput = stdinText != null;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = PkgDir;
        psi.StandardOutputEncoding = Encoding.UTF8;
        using (var p = Process.Start(psi))
        {
            if (stdinText != null)
            {
                p.StandardInput.Write(stdinText);
                p.StandardInput.Close();
            }
            string outp = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return outp;
        }
    }

    static Dictionary<string, object> Bridge(string action, string extra, string stdinText)
    {
        string raw = BridgeRaw(action, extra, stdinText);
        try
        {
            object o = new JavaScriptSerializer().DeserializeObject(raw);
            var d = o as Dictionary<string, object>;
            if (d != null) { return d; }
        }
        catch (Exception)
        {
        }
        var bad = new Dictionary<string, object>();
        bad["ok"] = false;
        bad["error"] = raw == null ? "no output from core" : raw.Trim();
        return bad;
    }

    static Dictionary<string, object> Bridge(string action) { return Bridge(action, null, null); }

    static bool Ok(Dictionary<string, object> d)
    {
        return d != null && d.ContainsKey("ok") && Convert.ToBoolean(d["ok"]);
    }
    static bool Bool(Dictionary<string, object> d, string k)
    {
        if (d == null || !d.ContainsKey(k) || d[k] == null) { return false; }
        return Convert.ToBoolean(d[k]);
    }
    static List<string> Strings(Dictionary<string, object> d, string k)
    {
        var list = new List<string>();
        if (d != null && d.ContainsKey(k) && d[k] is object[])
        {
            foreach (object o in (object[])d[k]) { if (o != null) { list.Add(Convert.ToString(o)); } }
        }
        return list;
    }
    static string Str(Dictionary<string, object> d, string k)
    {
        if (d == null || !d.ContainsKey(k) || d[k] == null) { return ""; }
        return Convert.ToString(d[k]);
    }
    static List<Dictionary<string, object>> Items(Dictionary<string, object> d, string k)
    {
        var list = new List<Dictionary<string, object>>();
        if (d != null && d.ContainsKey(k) && d[k] is object[])
        {
            foreach (object o in (object[])d[k])
            {
                var item = o as Dictionary<string, object>;
                if (item != null) { list.Add(item); }
            }
        }
        return list;
    }

    // ---------- ui ----------
    static Form Form1;
    static ListView List;
    static ProgressBar Bar;
    static Label Status;
    static Button BtnStart, BtnCheck, BtnKey, BtnData, BtnStop, BtnUninst, BtnRestore, BtnForce, BtnShortcut;
    static bool Starting;
    static string CurrentUrl = "";
    static int CurrentPort;

    static Font UiFont(float size, FontStyle style)
    {
        try { return new Font("Microsoft YaHei UI", size, style); }
        catch (Exception) { return new Font(FontFamily.GenericSansSerif, size, style); }
    }

    static void SetStatus(string s)
    {
        Status.Text = s;
    }

    static Button MakeButton(string text, int x, int y, int w, bool primary)
    {
        var b = new Button();
        b.Text = text;
        b.Location = new Point(x, y);
        b.Size = new Size(w, 40);
        b.FlatStyle = FlatStyle.Flat;
        b.Font = UiFont(10f, FontStyle.Regular);
        if (primary)
        {
            b.BackColor = Color.FromArgb(64, 110, 220);
            b.ForeColor = Color.White;
            b.FlatAppearance.BorderSize = 0;
        }
        else
        {
            b.BackColor = Color.White;
            b.ForeColor = Color.FromArgb(60, 60, 60);
            b.FlatAppearance.BorderColor = Color.FromArgb(200, 200, 205);
        }
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(235, 240, 255);
        return b;
    }

    static void BuildUi()
    {
        Form1 = new Form();
        Form1.Text = "DSH 便携版启动器  ·  DeepSeek Harness";
        Form1.Size = new Size(700, 620);
        Form1.StartPosition = FormStartPosition.CenterScreen;
        Form1.MinimumSize = new Size(700, 620);
        Form1.BackColor = Color.FromArgb(250, 250, 252);
        Form1.Font = UiFont(9f, FontStyle.Regular);
        string icon = Path.Combine(PkgDir, "assets\\dsh-whale.ico");
        try { if (File.Exists(icon)) { Form1.Icon = new Icon(icon); } }
        catch (Exception) { }

        var title = new Label();
        title.Text = "DeepSeek Harness";
        title.Font = UiFont(16f, FontStyle.Bold);
        title.ForeColor = Color.FromArgb(40, 60, 120);
        title.Location = new Point(20, 14);
        title.Size = new Size(420, 34);
        Form1.Controls.Add(title);

        var sub = new Label();
        sub.Text = "便携版 · 免安装 · 自带运行环境 · 不修改系统设置";
        sub.ForeColor = Color.Gray;
        sub.Location = new Point(23, 48);
        sub.Size = new Size(460, 20);
        Form1.Controls.Add(sub);

        List = new ListView();
        List.Location = new Point(20, 76);
        List.Size = new Size(645, 330);
        List.View = View.Details;
        List.FullRowSelect = true;
        List.GridLines = false;
        List.HeaderStyle = ColumnHeaderStyle.Nonclickable;
        List.MultiSelect = false;
        List.Columns.Add("状态", 62);
        List.Columns.Add("检查项", 120);
        List.Columns.Add("说明", 440);
        Form1.Controls.Add(List);

        Bar = new ProgressBar();
        Bar.Location = new Point(20, 414);
        Bar.Size = new Size(645, 8);
        Bar.Style = ProgressBarStyle.Continuous;
        Bar.Minimum = 0;
        Bar.Maximum = 100;
        Form1.Controls.Add(Bar);

        Status = new Label();
        Status.Text = "就绪";
        Status.ForeColor = Color.FromArgb(90, 90, 90);
        Status.Location = new Point(20, 428);
        Status.Size = new Size(645, 22);
        Form1.Controls.Add(Status);

        BtnStart = MakeButton("▶  启动 DSH", 20, 458, 150, true);
        BtnCheck = MakeButton("环境自检", 180, 458, 100, false);
        BtnKey = MakeButton("设置密钥", 290, 458, 100, false);
        BtnData = MakeButton("数据目录", 400, 458, 100, false);
        BtnStop = MakeButton("停止服务", 510, 458, 155, false);
        Form1.Controls.AddRange(new Control[] { BtnStart, BtnCheck, BtnKey, BtnData, BtnStop });

        BtnUninst = MakeButton("干净卸载…", 20, 506, 130, false);
        BtnRestore = MakeButton("还原初始状态", 158, 506, 130, false);
        BtnForce = MakeButton("强制覆盖…", 296, 506, 130, false);
        BtnShortcut = MakeButton("创建桌面快捷方式", 434, 506, 130, false);
        BtnForce.ForeColor = Color.FromArgb(170, 40, 40);
        BtnForce.FlatAppearance.BorderColor = Color.FromArgb(210, 150, 150);
        Form1.Controls.AddRange(new Control[] { BtnUninst, BtnRestore, BtnForce, BtnShortcut });

        var hint = new Label();
        hint.Text = "绿色便携版：不写入系统、不改 PATH / 注册表 / 用户目录；所有操作只影响本文件夹。";
        hint.ForeColor = Color.FromArgb(130, 130, 135);
        hint.Location = new Point(20, 556);
        hint.Size = new Size(645, 20);
        Form1.Controls.Add(hint);
    }

    static void UpdateChecks()
    {
        Dictionary<string, object> d = Bridge("envcheck");
        List.Items.Clear();
        int bad = 0;
        foreach (Dictionary<string, object> c in Items(d, "checks"))
        {
            string state = Str(c, "State");
            string tag = state == "ok" ? "✔  正常" : (state == "warn" ? "⚠  注意" : "✖  失败");
            var it = new ListViewItem(tag);
            it.SubItems.Add(Str(c, "Name"));
            it.SubItems.Add(Str(c, "Detail"));
            if (state == "ok") { it.ForeColor = Color.FromArgb(30, 140, 70); }
            else if (state == "warn") { it.ForeColor = Color.FromArgb(190, 130, 0); }
            else { it.ForeColor = Color.FromArgb(200, 40, 40); bad++; }
            List.Items.Add(it);
        }
        if (!Ok(d)) { bad++; SetStatus("自检无法运行：" + Str(d, "error")); }
        Dictionary<string, object> sc = Bridge("shortcut-state");
        BtnShortcut.Text = Bool(sc, "mine") ? "删除桌面快捷方式" : "创建桌面快捷方式";
        if (Ok(d))
        {
            SetStatus(bad > 0 ? ("自检完成：有 " + bad + " 项失败（见上表）") : "自检完成：全部通过，可以启动");
        }
    }

    static void OpenWeb(string url)
    {
        Bridge("open-web", "-Url \"" + url + "\"", null);
    }

    static void StartNow()
    {
        if (Starting) { return; }
        Dictionary<string, object> pf = Bridge("preflight");
        if (Bool(pf, "blocked"))
        {
            SetStatus("无法启动：这台电脑不满足运行要求（详见弹窗）");
            MessageBox.Show(Form1,
                "无法启动 —— 这台电脑不满足运行要求：\n\n" + Str(pf, "message") +
                "\n\n需要：64 位的 Windows 10 1809 (Build 17763) / Windows 11 及以上。",
                "无法启动", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        Dictionary<string, object> plan = Bridge("port-plan");
        int port = Convert.ToInt32(plan.ContainsKey("port") ? plan["port"] : 3080);
        if (Bool(plan, "ours"))
        {
            string cached = Str(plan, "cachedUrl");
            if (cached.Length > 0)
            {
                OpenWeb(cached);
                SetStatus("服务已在运行，已打开界面");
                return;
            }
            SetStatus("服务已在运行，但读不到 token，请先点「停止服务」再启动");
            return;
        }
        if (port <= 0) { SetStatus("3080 起连续端口都被占用，无法启动"); return; }
        if (Bool(plan, "defaultBusy"))
        {
            SetStatus("端口 3080 被占用，改用 " + port);
        }
        if (!Bool(Bridge("key-state"), "configured"))
        {
            SetStatus("提示：尚未配置 DeepSeek 密钥 —— 仍可启动，进界面后随时补填");
        }

        Starting = true;
        CurrentPort = port;
        Bar.Style = ProgressBarStyle.Marquee;
        SetStatus("正在启动服务（首次启动约 30-60 秒，请稍候）...");
        BtnStart.Enabled = false;

        int usePort = port;
        var t = new Thread(delegate ()
        {
            Dictionary<string, object> res = Bridge("start", "-Port " + usePort, null);
            try
            {
                Form1.BeginInvoke((MethodInvoker)delegate ()
                {
                    Starting = false;
                    BtnStart.Enabled = true;
                    Bar.Style = ProgressBarStyle.Continuous;
                    if (Ok(res) && Str(res, "url").Length > 0)
                    {
                        CurrentUrl = Str(res, "url");
                        Bar.Value = 100;
                        SetStatus("已启动：" + CurrentUrl);
                        OpenWeb(CurrentUrl);
                    }
                    else
                    {
                        Bar.Value = 0;
                        SetStatus("启动失败");
                        MessageBox.Show(Form1, "启动失败：\n\n" + Str(res, "error"),
                            "启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                });
            }
            catch (Exception) { }
        });
        t.IsBackground = true;
        t.Start();
    }

    static void KeyDialog()
    {
        var kf = new Form();
        kf.Text = "设置 DeepSeek API 密钥";
        kf.Size = new Size(480, 220);
        kf.StartPosition = FormStartPosition.CenterParent;
        kf.FormBorderStyle = FormBorderStyle.FixedDialog;
        kf.MaximizeBox = false; kf.MinimizeBox = false;
        kf.Font = UiFont(9f, FontStyle.Regular);

        var lb = new Label();
        lb.Text = "粘贴你的 DeepSeek API 密钥（sk- 开头），只保存在本文件夹的\nconfig\\api-key.txt 里，不会上传任何地方。";
        lb.Location = new Point(16, 14);
        lb.Size = new Size(440, 40);
        kf.Controls.Add(lb);

        var tb = new TextBox();
        tb.Location = new Point(16, 60);
        tb.Size = new Size(440, 26);
        tb.UseSystemPasswordChar = true;
        kf.Controls.Add(tb);

        var chk = new CheckBox();
        chk.Text = "显示密钥";
        chk.Location = new Point(16, 92);
        chk.Size = new Size(100, 24);
        chk.CheckedChanged += delegate { tb.UseSystemPasswordChar = !chk.Checked; };
        kf.Controls.Add(chk);

        var ok = new Button();
        ok.Text = "保存";
        ok.Location = new Point(250, 128);
        ok.Size = new Size(100, 32);
        ok.DialogResult = DialogResult.OK;
        var cancel = new Button();
        cancel.Text = "取消";
        cancel.Location = new Point(360, 128);
        cancel.Size = new Size(96, 32);
        cancel.DialogResult = DialogResult.Cancel;
        kf.Controls.AddRange(new Control[] { ok, cancel });
        kf.AcceptButton = ok;
        kf.CancelButton = cancel;

        if (kf.ShowDialog(Form1) == DialogResult.OK)
        {
            string v = tb.Text.Trim();
            if (v.Length < 20 || !v.StartsWith("sk-")) { SetStatus("密钥格式不对（DeepSeek 密钥以 sk- 开头，长 20 位以上），未保存"); return; }
            Dictionary<string, object> r = Bridge("set-key", null, v);
            if (Ok(r)) { SetStatus("密钥已保存到 config\\api-key.txt"); UpdateChecks(); }
            else { SetStatus("保存失败：" + Str(r, "error")); }
        }
    }

    static void UninstallDialog()
    {
        List<Dictionary<string, object>> items = Items(Bridge("uninstall-items"), "items");
        var uf = new Form();
        uf.Text = "干净卸载 —— 只清理本便携版自己的文件";
        uf.Size = new Size(620, 430);
        uf.StartPosition = FormStartPosition.CenterParent;
        uf.FormBorderStyle = FormBorderStyle.FixedDialog;
        uf.MaximizeBox = false; uf.MinimizeBox = false;
        uf.Font = UiFont(9f, FontStyle.Regular);

        var tip = new Label();
        tip.Text = "勾选要清理的项目。\n绝对不动系统里的东西：不改 PATH、不动 %USERPROFILE%\\.dsh、不卸载任何已装软件。";
        tip.Location = new Point(14, 10);
        tip.Size = new Size(580, 42);
        uf.Controls.Add(tip);

        var clist = new CheckedListBox();
        clist.Location = new Point(14, 56);
        clist.Size = new Size(580, 250);
        clist.CheckOnClick = true;
        foreach (Dictionary<string, object> it in items)
        {
            bool exists = Bool(it, "Exists");
            string txt = Str(it, "Name") + "  ——  " + (exists ? Str(it, "Detail") : "（不存在，跳过）");
            clist.Items.Add(txt, exists);
        }
        uf.Controls.Add(clist);

        var okU = new Button();
        okU.Text = "执行清理";
        okU.Location = new Point(360, 322);
        okU.Size = new Size(110, 34);
        var noU = new Button();
        noU.Text = "取消";
        noU.Location = new Point(484, 322);
        noU.Size = new Size(110, 34);
        noU.DialogResult = DialogResult.Cancel;
        uf.Controls.AddRange(new Control[] { okU, noU });
        uf.CancelButton = noU;

        okU.Click += delegate
        {
            var chosen = new List<string>();
            foreach (int idx in clist.CheckedIndices) { chosen.Add(Str(items[idx], "Key")); }
            if (chosen.Count == 0)
            {
                MessageBox.Show(uf, "没有勾选任何项目。", "提示", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            string warn = "将清理 " + string.Join("、", chosen.ToArray()) + "。";
            if (chosen.Contains("data")) { warn += "\n\n· 会删除全部会话记录、工作区、主题设置"; }
            if (chosen.Contains("key")) { warn += "\n\n· 会删除已保存的 API 密钥，下次要重新填"; }
            if (chosen.Contains("folder")) { warn += "\n\n· 会删除整个便携版文件夹，无法恢复"; }
            if (MessageBox.Show(uf, warn + "\n\n确定继续吗？", "确认清理",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) { return; }

            Dictionary<string, object> res = Bridge("uninstall", "-Keys " + string.Join(",", chosen.ToArray()), null);
            List<string> done = Strings(res, "done");
            List<string> bad = Strings(res, "failed");
            string msg = "已清理：" + string.Join("、", done.ToArray());
            if (bad.Count > 0) { msg += "\n\n未能清理：\n" + string.Join("\n", bad.ToArray()); }
            MessageBox.Show(uf, msg, "清理完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
            uf.Close();
        };
        uf.ShowDialog(Form1);
        UpdateChecks();
    }

    static void RestoreSeed()
    {
        if (!Ok(Bridge("restore")))
        {
            MessageBox.Show(Form1, "本包没有初始模板（seed\\.dsh），无法还原。", "无模板",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
    }

    static void ForceReset()
    {
        Dictionary<string, object> conf = Bridge("conflicts");
        var details = new List<string>();
        foreach (Dictionary<string, object> c in Items(conf, "items"))
        {
            if (Str(c, "Severity") == "conflict") { details.Add("  · " + Str(c, "Detail")); }
        }
        string detail = details.Count > 0 ? string.Join("\n", details.ToArray()) : "  · 当前没有检测到硬冲突";

        string m1 = "强制覆盖 = 重置本便携版的数据：\n\n  · data\\.dsh（会话 / 工作区 / 主题设置）\n  · 桌面快捷方式\n\n当前检测到的冲突：\n" + detail +
                    "\n\n本操作【不会】碰系统里的 dsh、PATH、注册表、用户目录。\n\n（第 1/3 次确认）继续吗？";
        if (MessageBox.Show(Form1, m1, "强制覆盖 · 1/3", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) { return; }

        string m2 = "第 2/3 次确认：\n\ndata\\.dsh 里的现有会话记录、工作区、主题设置会被【永久删除】，无法恢复。\n\n确定要继续吗？";
        if (MessageBox.Show(Form1, m2, "强制覆盖 · 2/3", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) { return; }

        var cf = new Form();
        cf.Text = "强制覆盖 · 3/3";
        cf.Size = new Size(470, 230);
        cf.StartPosition = FormStartPosition.CenterParent;
        cf.FormBorderStyle = FormBorderStyle.FixedDialog;
        cf.MaximizeBox = false; cf.MinimizeBox = false;
        cf.Font = UiFont(9f, FontStyle.Regular);

        var l1 = new Label();
        l1.Text = "最后一次确认：请在下面输入「覆盖」两个字。";
        l1.Location = new Point(16, 16);
        l1.Size = new Size(430, 24);
        cf.Controls.Add(l1);

        var t1 = new TextBox();
        t1.Location = new Point(16, 48);
        t1.Size = new Size(430, 26);
        cf.Controls.Add(t1);

        var l2 = new Label();
        l2.Text = "执行内容：清空并按包内初始模板还原 data\\.dsh，重建桌面快捷方式。";
        l2.ForeColor = Color.Gray;
        l2.Location = new Point(16, 82);
        l2.Size = new Size(430, 36);
        cf.Controls.Add(l2);

        var okF = new Button();
        okF.Text = "确认覆盖";
        okF.Location = new Point(216, 138);
        okF.Size = new Size(110, 32);
        okF.DialogResult = DialogResult.OK;
        var noF = new Button();
        noF.Text = "取消";
        noF.Location = new Point(336, 138);
        noF.Size = new Size(110, 32);
        noF.DialogResult = DialogResult.Cancel;
        cf.Controls.AddRange(new Control[] { okF, noF });
        cf.AcceptButton = okF;
        cf.CancelButton = noF;

        if (cf.ShowDialog(Form1) != DialogResult.OK) { return; }
        if (t1.Text.Trim() != "覆盖")
        {
            MessageBox.Show(Form1, "输入不匹配，已取消（未做任何改动）。", "已取消",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        SetStatus("正在强制覆盖...");
        Dictionary<string, object> r = Bridge("force-reset");
        if (Ok(r))
        {
            Dictionary<string, object> sc = Bridge("shortcut-state");
            string extra = "";
            if (Bool(sc, "mine"))
            {
                Bridge("shortcut-create");
                extra = "；桌面快捷方式已重建";
            }
            SetStatus("强制覆盖完成：data\\.dsh 已还原" + extra);
        }
        else { SetStatus("强制覆盖失败：" + Str(r, "error")); }
        UpdateChecks();
    }

    static void ShortcutToggle()
    {
        Dictionary<string, object> sc = Bridge("shortcut-state");
        bool mine = Bool(sc, "mine");
        if (mine)
        {
            if (MessageBox.Show(Form1,
                    "要删除桌面上的「DSH 便携版」快捷方式吗？\n\n只删这一个快捷方式，不影响程序本体和你的聊天数据。",
                    "删除桌面快捷方式", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) { return; }
            Dictionary<string, object> r = Bridge("shortcut-delete");
            SetStatus(Ok(r) ? "已删除桌面快捷方式" : ("未能删除：" + Str(r, "error")));
        }
        else
        {
            Dictionary<string, object> r = Bridge("shortcut-create");
            if (Ok(r)) { SetStatus(Str(r, "result") == "created" ? "已在桌面创建快捷方式" : "桌面已有指向本包的快捷方式"); }
            else { SetStatus("未创建：" + Str(r, "error")); }
        }
        UpdateChecks();
    }

    static void OnShown()
    {
        try
        {
            SetStatus("正在自检...");
            Form1.Refresh();
            UpdateChecks();

            Dictionary<string, object> pf = Bridge("preflight");
            if (Bool(pf, "blocked"))
            {
                SetStatus("环境不满足运行要求 —— 点「启动 DSH」可看到详细原因");
                if (!ShotMode)
                {
                    MessageBox.Show(Form1,
                        "这台电脑目前无法运行本便携版：\n\n" + Str(pf, "message") +
                        "\n\n（本包需要：64 位的 Windows 10 1809 / Windows 11 及以上）",
                        "环境检查未通过", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }

            Dictionary<string, object> sc = Bridge("shortcut-state");
            bool asked = Bool(sc, "asked");
            if (!ShotMode && !asked)
            {
                if (MessageBox.Show(Form1,
                        "要不要在桌面放一个启动快捷方式？\n\n不创建也完全不影响使用，\n以后随时可以在启动器里点「创建桌面快捷方式」。",
                        "快捷方式（可选）", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
                {
                    Dictionary<string, object> r = Bridge("shortcut-create");
                    SetStatus(Ok(r) ? "已在桌面创建快捷方式" : ("未创建：" + Str(r, "error")));
                }
                else { SetStatus("已跳过桌面快捷方式（随时可在启动器里创建）"); }
                Bridge("shortcut-asked-set");
                UpdateChecks();
            }
        }
        catch (Exception ex)
        {
            // A handler that throws before rendering leaves a blank window and no
            // trace; say what happened instead.
            try { SetStatus("自检出错：" + ex.Message); }
            catch (Exception) { }
        }
    }

    static bool ShotMode;
    static string ShotPath;

    [STAThread]
    static void Main(string[] args)
    {
        PkgDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        BridgePath = Path.Combine(PkgDir, "tools\\core-bridge.ps1");

        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "-Shot" && i + 1 < args.Length) { ShotMode = true; ShotPath = args[i + 1]; }
        }

        if (args.Length > 0 && args[0] == "--selftest")
        {
            // no console when built as winexe: this throws if not guarded
            try { Console.OutputEncoding = Encoding.UTF8; } catch (Exception) { }
            bool hasConsole = true;
            try { hasConsole = Console.Out != null; } catch (Exception) { hasConsole = false; }
            if (hasConsole) { Console.WriteLine("pkg=" + PkgDir); }
            string[] probe = new string[] { "version", "key-state", "port-plan", "shortcut-state", "envcheck", "preflight" };
            foreach (string a in probe)
            {
                string r = BridgeRaw(a, null, null);
                if (hasConsole)
                {
                    Console.WriteLine("[" + a + "] " + (r.Length > 160 ? r.Substring(0, 160) : r).Trim().Replace("\n", " "));
                }
                else
                {
                    File.AppendAllText(Path.Combine(PkgDir, "selftest.txt"), "[" + a + "] " + r + Environment.NewLine, Encoding.UTF8);
                }
            }
            return;
        }

        if (!File.Exists(BridgePath))
        {
            MessageBox.Show(
                "找不到 tools\\core-bridge.ps1。\n\n请确认整个文件夹已完整解压（不要只复制 exe 单个文件）。",
                "DSH 便携版", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        Application.EnableVisualStyles();
        BuildUi();

        BtnStart.Click += delegate { StartNow(); };
        BtnCheck.Click += delegate { SetStatus("正在自检..."); Form1.Refresh(); UpdateChecks(); };
        BtnKey.Click += delegate { KeyDialog(); };
        BtnData.Click += delegate { Process.Start("explorer.exe", "\"" + PkgDir + "\""); };
        BtnStop.Click += delegate
        {
            Dictionary<string, object> r = Bridge("stop", "-Port " + (CurrentPort > 0 ? CurrentPort : 3080), null);
            SetStatus(Bool(r, "stopped") ? "服务已停止" : "没有由本便携版启动的服务");
        };
        BtnUninst.Click += delegate { UninstallDialog(); };
        BtnRestore.Click += delegate { RestoreSeed(); };
        BtnForce.Click += delegate { ForceReset(); };
        BtnShortcut.Click += delegate { ShortcutToggle(); };

        if (ShotMode)
        {
            // Render, save, exit - lets a human (or a test) see the real window
            // without clicking anything.
            Form1.Shown += delegate
            {
                try { OnShown(); }
                catch (Exception) { }
                var bmp = new Bitmap(Form1.Width, Form1.Height);
                try
                {
                    Form1.DrawToBitmap(bmp, new Rectangle(0, 0, Form1.Width, Form1.Height));
                    bmp.Save(ShotPath, System.Drawing.Imaging.ImageFormat.Png);
                }
                catch (Exception ex)
                {
                    try { File.WriteAllText(ShotPath + ".err.txt", ex.GetType().Name + ": " + ex.Message, Encoding.UTF8); }
                    catch (Exception) { }
                }
                bmp.Dispose();
                Form1.Close();
            };
            Application.Run(Form1);
            return;
        }

        Form1.Shown += delegate { OnShown(); };
        Application.Run(Form1);
    }
}
