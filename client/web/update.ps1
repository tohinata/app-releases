# 공통 업데이터 (윈도우 · 폴더째 배포하는 HTML 앱용).
#
# 원본: app-releases/client/web/update.ps1 — 고칠 때는 원본을 고치고 9-1_공통업데이터복사.bat 으로 다시 복사한다.
# 실행 배치(1-1_실행.bat)가 앱을 열기 전에 부른다:
#   powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -App <앱키> -Name <이름>
#
# 같은 폴더의 version.txt 와 공개 저장소 tohinata/app-releases 의 manifest/<앱키>.json 을 비교해
# 새 버전이면 묻고, zip 을 받아(진행 창) SHA-256 확인 뒤 이 폴더에 덮어쓴다. 실패하면 원래대로 되돌린다.
# 인터넷이 없거나 최신이면 아무것도 보이지 않고 바로 끝난다.
# 이 폴더가 git 저장소(개발 폴더)면 건너뛴다 — 고치던 파일을 덮어쓰지 않게.
param(
    [Parameter(Mandatory = $true)][string]$App,
    [Parameter(Mandatory = $true)][string]$Name
)
$ErrorActionPreference = 'Stop'
$Dir = $PSScriptRoot
if (Test-Path -LiteralPath (Join-Path $Dir '.git')) { exit 0 }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $local = '0.0.0'
    $vf = Join-Path $Dir 'version.txt'
    if (Test-Path -LiteralPath $vf) { $local = ([IO.File]::ReadAllText($vf)).Trim() }

    $url = "https://raw.githubusercontent.com/tohinata/app-releases/main/manifest/$App.json?t=" + [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 60)
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'coarsoft-updater'
    $req.Timeout = 5000
    $resp = $req.GetResponse()
    $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
    $info = $sr.ReadToEnd().TrimStart([char]0xFEFF) | ConvertFrom-Json
    $sr.Close(); $resp.Close()

    function V([string]$s) { $p = @($s.Split('.') | ForEach-Object { [int]("0" + ($_ -replace '\D', '')) }); while ($p.Count -lt 3) { $p += 0 }; return New-Object Version($p[0], $p[1], $p[2]) }
    if ((V $info.version) -le (V $local)) { exit 0 }
}
catch { exit 0 }   # 인터넷이 없거나 아직 올린 적이 없으면 조용히

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$notes = "$($info.notes)".Trim()
if ($notes.Length -gt 1000) { $notes = $notes.Substring(0, 1000) + '…' }
$ask = [Windows.Forms.MessageBox]::Show(
    "$Name 새 버전이 있습니다.`n`n지금 $local → $($info.version)`n`n$notes`n`n지금 업데이트할까요?",
    "$Name 업데이트", 'YesNo', 'Information')
if ($ask -ne 'Yes') { exit 0 }

$work = Join-Path $env:TEMP ('coarsoft-update\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

$form = New-Object Windows.Forms.Form
$form.Text = "$Name 업데이트 $($info.version)"
$form.ClientSize = New-Object Drawing.Size(440, 96)
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition = 'CenterScreen'
$form.ControlBox = $false
$form.TopMost = $true
$label = New-Object Windows.Forms.Label
$label.SetBounds(16, 16, 408, 24)
$bar = New-Object Windows.Forms.ProgressBar
$bar.SetBounds(16, 48, 408, 22)
$bar.Maximum = 1000
$form.Controls.Add($label)
$form.Controls.Add($bar)
$form.Show()
function Say([string]$t, [double]$r) { $label.Text = $t; if ($r -ge 0) { $bar.Value = [Math]::Max(0, [Math]::Min(1000, [int]($r * 1000))) }; [Windows.Forms.Application]::DoEvents() }

$backups = New-Object System.Collections.ArrayList
$added = New-Object System.Collections.ArrayList
try {
    $zip = Join-Path $work 'update.zip'
    $req = [Net.HttpWebRequest]::Create($info.url)
    $req.UserAgent = 'coarsoft-updater'
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $in = $resp.GetResponseStream()
    $out = [IO.File]::Create($zip)
    try {
        $buf = New-Object byte[] 262144
        $got = 0L
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $got += $n
            if ($total -gt 0) { Say ('받는 중… {0:N1} / {1:N1} MB' -f ($got / 1MB), ($total / 1MB)) ($got / $total) }
        }
    } finally { $out.Close(); $in.Close(); $resp.Close() }

    Say '받은 파일 확인 중…' 1
    if ($info.sha256 -and (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne "$($info.sha256)".ToUpperInvariant()) {
        throw '받은 파일이 손상되었습니다 (SHA-256 불일치).'
    }
    $new = Join-Path $work 'new'
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $new)
    $new = (Get-Item -LiteralPath $new).FullName.TrimEnd('\')

    # keep 은 'a/b.json' · 'a\b.json' 어느 쪽으로 써도 되게 / 로 맞춰 비교한다
    $keep = @($info.keep | Where-Object { $_ } | ForEach-Object { "$_".Replace('\', '/').TrimStart('/') })
    $old = Join-Path $work 'old'
    $files = @(Get-ChildItem -Path $new -Recurse -File)
    $i = 0
    foreach ($f in $files) {
        $i++
        $rel = $f.FullName.Substring($new.Length).TrimStart('\')
        $dst = Join-Path $Dir $rel
        if (($keep -contains $rel.Replace('\', '/')) -and (Test-Path -LiteralPath $dst)) { continue }
        Say ('설치 중… {0} / {1}' -f $i, $files.Count) ($i / [Math]::Max(1, $files.Count))
        $dd = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
        if (Test-Path -LiteralPath $dst) {
            $bak = Join-Path $old $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $bak) -Force | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak -Force
            [void]$backups.Add(@($dst, $bak))
        } else { [void]$added.Add($dst) }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    }
    Say "업데이트했습니다 ($($info.version))." 1
    Start-Sleep -Milliseconds 600
}
catch {
    $err = $_.Exception.Message
    foreach ($p in $backups) { try { Copy-Item -LiteralPath $p[1] -Destination $p[0] -Force } catch {} }
    foreach ($a in $added) { try { Remove-Item -LiteralPath $a -Force } catch {} }
    try { $form.Hide() } catch {}
    [Windows.Forms.MessageBox]::Show("업데이트하지 못했습니다.`n`n$err`n`n원래 버전 그대로 엽니다.", "$Name 업데이트") | Out-Null
}
finally {
    try { $form.Close() } catch {}
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
