# PC 업데이트 (윈도우 · C#)

공용 `client/windows/AppUpdater.cs`(`Coarsoft.Update`), WPF/WinForms 비의존.

- 시작 시 1회 + "업데이트 확인" 메뉴. manifest 를 raw 에서 읽음(`?t=` 캐시회피).
- 현재 `<Version>` vs manifest `version` → 새 버전이면 묻고 [예] 시 **업데이트 PowerShell 스크립트** 띄우고 종료 → 받기→SHA-256→종료 대기→덮어쓰기→재실행, 실패 시 **롤백**.
- `keep` 파일은 안 덮음. 폴더배포=압축 풀어 덮기, 단일=exe 교체.
- manifest `platform:"windows"`, `exe`, 필요 시 `keep`.
- 원본 수정: `client/windows/AppUpdater.cs` 고치고 `9-1`.
