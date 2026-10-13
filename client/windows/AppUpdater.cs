// 공통 앱 업데이터 (윈도우).
//
// 원본: app-releases/client/windows/AppUpdater.cs — 고칠 때는 원본을 고치고
// app-releases/sync-clients.bat 으로 모든 프로그램에 다시 복사한다.
//
// 공개 저장소 tohinata/app-releases 의 manifest/<앱키>.json 을 읽어 지금보다 새 버전이면 묻고,
// 「예」면 업데이트 스크립트(PowerShell)를 띄운 뒤 프로그램을 닫는다. 스크립트가
//   받기(진행 창) → SHA-256 확인 → 프로그램이 닫히기를 기다림 → 파일 덮어쓰기 → 다시 실행
// 을 한다. 덮어쓰다 실패하면 원래 파일로 되돌린다.
//
// WPF · WinForms 어느 쪽에도 의존하지 않는다 — 묻는 창(confirm)과 닫기(close)는 프로그램이 넘겨준다.

#nullable enable

using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace Coarsoft.Update
{
    public sealed class UpdateInfo
    {
        public string Version { get; set; } = "";
        public string Url { get; set; } = "";
        public string Sha256 { get; set; } = "";
        public long Size { get; set; }
        public string Notes { get; set; } = "";
        public string Exe { get; set; } = "";
        public string[] Keep { get; set; } = Array.Empty<string>();
    }

    public static class AppUpdater
    {
        private const string ManifestUrl = "https://raw.githubusercontent.com/tohinata/app-releases/main/manifest/{0}.json";

        /// <summary>
        /// 지금 버전 = csproj 의 &lt;Version&gt; (InformationalVersion).
        /// AssemblyVersion 은 따로 적어 둔 프로젝트가 있어 &lt;Version&gt; 만 올리면 어긋날 수 있다.
        /// </summary>
        public static Version CurrentVersion
        {
            get
            {
                var asm = Assembly.GetEntryAssembly();
                var info = asm?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
                if (info != null)
                {
                    var core = info.Split('+', '-')[0];
                    if (Version.TryParse(core, out var iv)) return Normalize(iv);
                }
                return Normalize(asm?.GetName().Version ?? new Version(0, 0, 0));
            }
        }

        /// <summary>새 버전이 있으면 그 정보, 없거나 확인할 수 없으면 null. 예외를 던지지 않는다.</summary>
        public static async Task<UpdateInfo?> CheckAsync(string appKey)
        {
            try
            {
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
                http.DefaultRequestHeaders.UserAgent.ParseAdd("coarsoft-updater");
                // raw.githubusercontent.com 은 몇 분 캐시한다. 1분 단위 쿼리로 너무 오래된 값을 피한다.
                var url = string.Format(ManifestUrl, appKey) + "?t=" + (DateTime.UtcNow.Ticks / TimeSpan.TicksPerMinute);
                var json = (await http.GetStringAsync(url).ConfigureAwait(false)).TrimStart('﻿');

                using var doc = JsonDocument.Parse(json);
                var r = doc.RootElement;
                var info = new UpdateInfo
                {
                    Version = Str(r, "version"),
                    Url = Str(r, "url"),
                    Sha256 = Str(r, "sha256"),
                    Size = r.TryGetProperty("size", out var s) && s.ValueKind == JsonValueKind.Number ? s.GetInt64() : 0,
                    Notes = Str(r, "notes"),
                    Exe = Str(r, "exe")
                };
                if (r.TryGetProperty("keep", out var k) && k.ValueKind == JsonValueKind.Array)
                {
                    var list = new System.Collections.Generic.List<string>();
                    foreach (var e in k.EnumerateArray())
                        if (e.ValueKind == JsonValueKind.String) list.Add(e.GetString() ?? "");
                    info.Keep = list.ToArray();
                }

                if (!Version.TryParse(info.Version, out var latest) || info.Url.Length == 0) return null;
                return Normalize(latest) > CurrentVersion ? info : null;
            }
            catch
            {
                return null;   // 인터넷이 없거나 아직 올린 적이 없으면 조용히 넘어간다
            }
        }

        /// <summary>
        /// 프로그램 시작 때 한 번 부른다 (UI 스레드에서 await).
        /// </summary>
        /// <param name="appKey">릴리스 저장소의 앱 키 (예: subsyncstudio)</param>
        /// <param name="appName">사람이 읽는 이름 (예: 싱크 스튜디오)</param>
        /// <param name="confirm">물어볼 말 → 「예」면 true. 프로그램의 메시지 상자로.</param>
        /// <param name="close">프로그램 닫기 (주 창 Close 등)</param>
        public static async Task CheckOnStartupAsync(string appKey, string appName, Func<string, bool> confirm, Action close)
        {
            var info = await CheckAsync(appKey);
            if (info == null) return;

            var size = info.Size > 0 ? $" · {info.Size / 1048576.0:0.0}MB" : "";
            var notes = info.Notes.Trim();
            if (notes.Length > 1200) notes = notes.Substring(0, 1200) + "…";
            var msg = $"{appName} 새 버전이 있습니다.\n\n지금 {Show(CurrentVersion)} → {info.Version}{size}\n\n" +
                      (notes.Length > 0 ? notes + "\n\n" : "") +
                      "지금 업데이트할까요? 프로그램이 닫히고, 업데이트가 끝나면 다시 열립니다.";
            if (!confirm(msg)) return;

            if (Start(info, appName)) close();
        }

        /// <summary>업데이트 스크립트를 띄운다. 띄웠으면 true — 그 뒤 프로그램을 닫아야 진행된다.</summary>
        public static bool Start(UpdateInfo info, string appName)
        {
            try
            {
                var dir = AppContext.BaseDirectory.TrimEnd('\\', '/');
                var exe = info.Exe.Length > 0
                    ? info.Exe
                    : Path.GetFileName(Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName ?? "");

                var work = Path.Combine(Path.GetTempPath(), "coarsoft-update");
                Directory.CreateDirectory(work);
                var script = Path.Combine(work, "update-" + Guid.NewGuid().ToString("N") + ".ps1");
                // PowerShell 5.1 은 BOM 이 있어야 UTF-8 한글을 바르게 읽는다
                File.WriteAllText(script, Script, new UTF8Encoding(true));

                var psi = new ProcessStartInfo("powershell.exe")
                {
                    // 콘솔 창만 숨긴다. WindowStyle=Hidden 을 주면 .NET 8 에서는 진행 창(WinForms)까지 숨겨진다.
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                foreach (var a in new[]
                {
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
                    "-ProcId", Environment.ProcessId.ToString(),
                    "-Url", info.Url,
                    "-Sha", info.Sha256,
                    "-Dir", dir,
                    "-Exe", exe,
                    "-Name", appName,
                    "-Version", info.Version,
                    "-Keep", string.Join(";", info.Keep)
                })
                    psi.ArgumentList.Add(a);

                Process.Start(psi);
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static string Str(JsonElement r, string name) =>
            r.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";

        /// <summary>0.1.1.0 과 0.1.1 을 같게 본다.</summary>
        private static Version Normalize(Version v) =>
            new Version(Math.Max(0, v.Major), Math.Max(0, v.Minor), Math.Max(0, v.Build));

        private static string Show(Version v) => $"{v.Major}.{v.Minor}.{v.Build}";

        // ------------------------------------------------------------------ 업데이트 스크립트

        private const string Script = """
param(
    [int]$ProcId,
    [string]$Url,
    [string]$Sha,
    [string]$Dir,
    [string]$Exe,
    [string]$Name,
    [string]$Version,
    [string]$Keep
)
# 공통 업데이터가 띄우는 스크립트 (AppUpdater.cs 안에 들어 있다).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$log = Join-Path $env:TEMP 'coarsoft-update\update.log'
function Log([string]$m) { try { Add-Content -Path $log -Value ("{0} [{1} {2}] {3}" -f (Get-Date -Format s), $Name, $Version, $m) -Encoding UTF8 } catch {} }

$work = Join-Path $env:TEMP ('coarsoft-update\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

# ---------------------------------------------------------------- 진행 창
$form = New-Object Windows.Forms.Form
$form.Text = "$Name 업데이트 $Version"
$form.ClientSize = New-Object Drawing.Size(440, 96)
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition = 'CenterScreen'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.ControlBox = $false
$script:closing = $false
$form.Add_FormClosing({ if (-not $script:closing) { $_.Cancel = $true } })
$label = New-Object Windows.Forms.Label
$label.SetBounds(16, 16, 408, 24)
$label.Text = '준비 중…'
$bar = New-Object Windows.Forms.ProgressBar
$bar.SetBounds(16, 48, 408, 22)
$bar.Minimum = 0
$bar.Maximum = 1000
$form.Controls.Add($label)
$form.Controls.Add($bar)
$form.Show()
[Windows.Forms.Application]::DoEvents()

function Say([string]$text, [double]$ratio) {
    $label.Text = $text
    if ($ratio -ge 0) { $bar.Value = [Math]::Max(0, [Math]::Min(1000, [int]($ratio * 1000))) }
    [Windows.Forms.Application]::DoEvents()
}

$backups = New-Object System.Collections.ArrayList   # (원래 파일, 백업 파일)
$added = New-Object System.Collections.ArrayList     # 새로 생긴 파일
$ok = $false
try {
    # 1) 받기
    $zip = Join-Path $work 'update.zip'
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.UserAgent = 'coarsoft-updater'
    $req.AllowAutoRedirect = $true
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($zip)
    try {
        $buf = New-Object byte[] 262144
        $got = 0L
        $tick = [Environment]::TickCount
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n)
            $got += $n
            if ([Environment]::TickCount - $tick -gt 100) {
                $tick = [Environment]::TickCount
                if ($total -gt 0) { Say ('받는 중… {0:N1} / {1:N1} MB' -f ($got / 1MB), ($total / 1MB)) ($got / $total) }
                else { Say ('받는 중… {0:N1} MB' -f ($got / 1MB)) -1 }
            }
        }
    } finally { $out.Close(); $in.Close(); $resp.Close() }

    # 2) 확인
    Say '받은 파일 확인 중…' 1
    if ($Sha) {
        $h = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
        if ($h -ne $Sha.ToUpperInvariant()) { throw '받은 파일이 손상되었습니다 (SHA-256 불일치). 다시 시도하세요.' }
    }
    $new = Join-Path $work 'new'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $new)
    # %TEMP% 이 짧은 이름(ABCDEF~1)일 수 있어 실제 긴 경로로 맞춘다 (아래 상대 경로 계산용)
    $new = (Get-Item -LiteralPath $new).FullName.TrimEnd('\')

    # 3) 프로그램이 닫히기를 기다린다
    $deadline = (Get-Date).AddSeconds(90)
    while (Get-Process -Id $ProcId -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) { throw "$Name 이(가) 닫히지 않아 업데이트를 취소했습니다. 프로그램을 닫은 뒤 다시 실행하면 다시 묻습니다." }
        Say "$Name 이(가) 닫히기를 기다리는 중…" 1
        Start-Sleep -Milliseconds 300
    }
    Start-Sleep -Milliseconds 700

    # 4) 덮어쓰기 (원래 파일은 백업해 두었다가 실패하면 되돌린다)
    $keepList = @($Keep -split ';' | Where-Object { $_ })
    $old = Join-Path $work 'old'
    $files = @(Get-ChildItem -Path $new -Recurse -File)
    $i = 0
    foreach ($f in $files) {
        $i++
        $rel = $f.FullName.Substring($new.Length).TrimStart('\')
        $dst = Join-Path $Dir $rel
        if (($keepList -contains $rel) -and (Test-Path -LiteralPath $dst)) { continue }
        Say ('설치 중… {0} / {1}' -f $i, $files.Count) ($i / [Math]::Max(1, $files.Count))

        $dd = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
        if (Test-Path -LiteralPath $dst) {
            $bak = Join-Path $old $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $bak) -Force | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak -Force
            [void]$backups.Add(@($dst, $bak))
        } else {
            [void]$added.Add($dst)
        }
        # 백신 검사 등으로 잠깐 잠겨 있을 수 있어 몇 번 다시 시도한다
        for ($try = 1; $try -le 20; $try++) {
            try { Copy-Item -LiteralPath $f.FullName -Destination $dst -Force; break }
            catch { if ($try -eq 20) { throw }; Start-Sleep -Milliseconds 500 }
        }
    }
    $ok = $true
    Log 'updated'
    Say "업데이트했습니다. $Name 을(를) 다시 엽니다." 1
    Start-Sleep -Milliseconds 700
}
catch {
    $err = $_.Exception.Message
    Log ('FAILED: ' + $err)
    # 되돌리기
    foreach ($p in $backups) { try { Copy-Item -LiteralPath $p[1] -Destination $p[0] -Force } catch {} }
    foreach ($a in $added) { try { Remove-Item -LiteralPath $a -Force } catch {} }
    try { $form.Hide() } catch {}
    [Windows.Forms.MessageBox]::Show("업데이트하지 못했습니다.`n`n$err`n`n원래 버전 그대로 다시 엽니다.", "$Name 업데이트") | Out-Null
}
finally {
    $script:closing = $true
    try { $form.Close() } catch {}
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# 다시 실행 (업데이트에 실패해도 원래 프로그램을 연다)
$target = Join-Path $Dir $Exe
if (-not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $target)) {
    Start-Process -FilePath $target -WorkingDirectory $Dir
}
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
""";
    }
}
