# PC 개발 (윈도우 · C#)

- C#/.NET, UI 는 WPF 또는 WinForms. 공용 업데이터는 둘에 비의존(확인창·종료를 콜백으로 받음).
- 버전 `.csproj <Version>1.2.3</Version>`. 배포 `dotnet publish`→zip/단일exe→릴리스.
- 업데이터는 `Services/AppUpdater.cs`(또는 `apps.ps1` 의 `Target` 경로), 네임스페이스 `Coarsoft.Update`.

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
