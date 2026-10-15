# PC 개발 (윈도우 · C#)

- C#/.NET, UI 는 WPF 또는 WinForms. 공용 업데이터는 둘에 비의존(확인창·종료를 콜백으로 받음).
- 버전 `.csproj <Version>1.2.3</Version>`. 배포 `dotnet publish`→zip/단일exe→릴리스.
- 업데이터는 `Services/AppUpdater.cs`(또는 `apps.ps1` 의 `Target` 경로), 네임스페이스 `Coarsoft.Update`.

## 포터블 (exe 하나)
- 모든 PC 앱에 `2-2_exe하나로만들기.bat` — `dist\single\<Exe>` 에 exe 한 개(.NET 포함).
  LibVLC·Whisper 처럼 **옆 폴더를 찾는 네이티브가 있으면 `IncludeAllContentForSelfExtract` 를 반드시 넣는다**
  (없으면 재생이 안 되고 빌드 때는 아무 경고도 없다).
- **데이터는 설치판과 같은 곳을 쓴다.** 저장 위치를 `%LOCALAPPDATA%`/`%APPDATA%\<앱>` 처럼
  **exe 위치와 무관하게** 잡아야 폴더판으로 쓰다가 포터블로 열어도 기록이 이어진다.
  실행 폴더에 저장하면 포터블을 다른 폴더에 두는 순간 빈 앱이 된다 — 그래서 실행 폴더 저장은 쓰지 않는다.
  배치 파일 안내에도 어디를 쓰는지 한 줄 적어 둔다.
- 릴리스에도 같이 올리려면 `4-1` 의 `release-windows.ps1` 호출에 `-Portable`
  (`-Mode folder` 일 때만. `-Mode single` 은 릴리스 자산 자체가 exe 하나라 필요 없다).

## 지킬 것
테마 색 리소스화 · 정보화면 개발자/저작권 · CHANGELOG 공통 · 시작 시+메뉴 업데이트확인 · 외부 의존 최소(LibVLC 등만, 그 경우 `-Mode folder`).

## 배포 (release-windows.ps1)
- `-Mode folder`(DLL 폴더째) / `-Mode single`(exe 하나)
- `-Keep a;b` 업데이트 때 안 덮을 사용자 데이터 · `-Exe` 실행 파일
```
powershell -File ..\app-releases\tools\release-windows.ps1 -Project "%~dp0." ^
  -App subsyncstudio -Name "싱크 스튜디오" -Csproj "src\...\X.csproj" -Exe "X.exe" -Mode folder -Keep "settings.json"
```
사용자 설정은 `-Keep` 으로 보존. 저장 위치는 실행 폴더 또는 `%APPDATA%` 중 하나로.
