# PC 업데이트 (윈도우 · C#)

공용 `client/windows/AppUpdater.cs`(`Coarsoft.Update`), WPF/WinForms 비의존.

- 시작 시 1회 + "업데이트 확인" 메뉴. manifest 를 raw 에서 읽음(`?t=` 캐시회피).
- 현재 `<Version>` vs manifest `version` → 새 버전이면 묻고 [예] 시 **업데이트 PowerShell 스크립트** 띄우고 종료 → 받기→SHA-256→종료 대기→덮어쓰기→재실행, 실패 시 **롤백**.
- `keep` 파일은 안 덮음. 폴더배포=압축 풀어 덮기, 단일=exe 교체.
- **포터블(exe 하나)**: `release-windows.ps1 -Mode folder -Portable` 이면 같은 릴리스에 `<앱키>-<버전>-portable.exe` 도 올리고
  manifest 에 `portable:{url,sha256,size}` 를 넣는다. 앱은 `AppUpdater.IsPortable`(BaseDirectory≠exe 폴더 또는 Location 비어 있음)로
  포터블 실행을 알아내 portable 쪽을 받아 **exe 가 있는 폴더의 그 exe**(이름 그대로)만 교체. 그 릴리스에 portable 이 없으면 업데이트를 묻지 않는다.
  LibVLC 같은 옆 폴더가 필요한 앱도 되도록 포터블은 `IncludeAllContentForSelfExtract` 로 빌드.
- manifest `platform:"windows"`, `exe`, 필요 시 `keep`.
- 원본 수정: `client/windows/AppUpdater.cs` 고치고 `9-1`.
