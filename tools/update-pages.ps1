# 다운로드 페이지(README 표 · apps\*.md)를 다시 만들고, 지금 릴리스들의 설명 맨 위에 받기 링크를 넣는다.
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Gh
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # gh 출력(UTF-8)의 한글이 깨지지 않게
git -C $Root pull --ff-only -q 2>$null

Step "릴리스 설명 맨 위에 받기 링크 넣기"
foreach ($mf in Get-ChildItem -Path (Join-Path $Root 'manifest') -Filter *.json) {
    $m = [IO.File]::ReadAllText($mf.FullName) | ConvertFrom-Json
    $tag = "$($m.app)-v$($m.version)"
    $body = (@(gh release view $tag -R $RepoFull --json body --jq .body 2>$null) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0) { Say "건너뜀 (릴리스 없음): $tag"; continue }
    if ($body -match '⬇ 받기') { Say "그대로: $tag"; continue }
    $file = [Uri]::UnescapeDataString(("$($m.url)" -split '/')[-1])
    $nf = Join-Path $env:TEMP "release-notes-$($m.app).md"
    [IO.File]::WriteAllText($nf, "### ⬇ 받기: [$file]($($m.url))`n`n$body", (New-Object Text.UTF8Encoding($false)))
    gh release edit $tag -R $RepoFull --notes-file $nf | Out-Null
    Remove-Item $nf -ErrorAction SilentlyContinue
    Say "고침: $tag"
}

Step "다운로드 페이지 만들기 (README · apps\)"
Update-Pages
Say "만들었습니다. 3-1_커밋+올리기.bat 으로 올리면 GitHub 에 보입니다."
