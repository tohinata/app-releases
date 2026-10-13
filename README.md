# app-releases

온천장 (tohinata) 의 앱 배포용 공개 저장소입니다. **소스는 없고** 설치 파일(릴리스)과 버전 정보만 있습니다.
각 앱은 실행할 때 `manifest/<앱키>.json` 을 읽어 새 버전이 있으면 업데이트를 묻습니다.

| 앱 | 앱키 | 종류 |
|---|---|---|
| 싱크 스튜디오 모바일 | `subsyncmobile` | 안드로이드 |
| 따라말해 | `midrepeat` | 안드로이드 |
| 오토클릭 | `autoclicker` | 안드로이드 |
| 인스타 받기 | `instaget` | 안드로이드 |
| 싱크 스튜디오 | `subsyncstudio` | 윈도우 |
| 받아쓰기 스튜디오 | `middictation` | 윈도우 |
| 서평 스튜디오 | `bookreviewstudio` | 윈도우 |
| MKV 일괄 병합기 | `mkvbatchmerger` | 윈도우 |
| 파일 이름 규칙 | `mediarenamer` | 윈도우 |
| 앱테크 체크 | `apptech` | 안드로이드 (Capacitor) |
| 도서 서평 관리 | `bookreviewapp` | 안드로이드 (Capacitor) |
| 태그 복사 | `tagcopy` | 안드로이드 (Capacitor) |
| 리치 마작 가이드 | `riichiguide` | 안드로이드 (Capacitor) |
| 신장의 야망 16 한자 매뉴얼 | `nobunaga16` | 윈도우 (HTML, run-app.bat) |
| 댓글 문구 순서 복사기 | `commentcopier` | 크롬 확장 (알림까지) |
| 네이버 페이 URL 파서 | `urlparser` | 크롬 확장 (알림까지) |

---

## 새 버전 올리는 법

1. 프로젝트에서 버전을 올린다
   - 안드로이드: `app/build.gradle.kts` 의 `versionCode` (+1) 와 `versionName`
   - Capacitor 앱: `android/app/build.gradle` 의 `versionCode` (+1) 와 `versionName`
   - 윈도우: `.csproj` 의 `<Version>`
   - HTML 앱: `version.txt` · 크롬 확장: `manifest.json` 의 `version`
2. `CHANGELOG.md` 맨 위에 `## 0.2.0 — 날짜` 절을 쓴다 (이 부분이 업데이트 안내 창에 나온다)
3. 프로젝트 폴더의 **`release.bat`** 실행 — 빌드 → 이 저장소에 릴리스 → `manifest` 갱신까지 한 번에

같은 버전을 두 번 올리려 하면 멈춥니다 (버전을 먼저 올리세요).

## 처음 한 번

1. GitHub CLI 설치 · 로그인: `winget install GitHub.cli` → 새 창에서 `gh auth login`
2. 이 폴더의 **`init.bat`** — 공개 저장소 `tohinata/app-releases` 를 만들고 올린다
3. 안드로이드 기기: 지금 깔린 앱(디버그 키로 서명됨)을 **한 번 지우고** 새 버전을 설치한다
   - 이제부터 `install.bat` 도 배포용 키로 서명하므로, USB 설치본과 업데이트본이 서로 덮어써진다
   - 각 프로젝트의 `keystore\` 와 `keystore.properties` 는 꼭 백업 (잃어버리면 다시 지우고 깔아야 함)

## 동작

```
manifest/<앱키>.json
{
  "app": "subsyncmobile", "name": "싱크 스튜디오 모바일", "platform": "android",
  "version": "0.2.0", "versionCode": 2,
  "url": "https://github.com/tohinata/app-releases/releases/download/subsyncmobile-v0.2.0/SubSyncMobile-0.2.0.apk",
  "sha256": "…", "size": 12345678, "notes": "CHANGELOG 의 그 버전 부분",
  "exe": "…(윈도우)", "keep": ["…(윈도우: 덮어쓰지 않을 사용자 파일)"]
}
```

- **안드로이드** (`client/android/AppUpdater.kt`): 앱 시작 때 확인 → 「업데이트」 → APK 받기(진행 표시) → SHA-256 · 패키지 확인 → 설치 창.
  기기마다 처음 한 번 「출처를 알 수 없는 앱 설치」 허용이 필요합니다. 앱 정보 화면의 버전을 누르면 바로 확인합니다.
- **윈도우** (`client/windows/AppUpdater.cs`): 시작 때 확인 → 「예」 → 프로그램이 닫히고 업데이트 창(PowerShell)이
  zip 받기 → SHA-256 확인 → 파일 덮어쓰기(실패하면 원래대로) → 다시 실행. 로그: `%TEMP%\coarsoft-update\update.log`

- **Capacitor 앱** (`client/android-java/`): 안드로이드와 같다 (Java 판).
- **HTML 앱** (`client/web/update.ps1`): `run-app.bat` 이 열기 전에 확인 → 받기 → 덮어쓰기. 폴더가 git 저장소(개발 폴더)면 건너뛴다.
- **크롬 확장** (`client/chrome/update-check.js`): 압축 해제 설치본은 크롬이 스스로 바꿀 수 없어서, 아이콘에 NEW 를 띄우고
  팝업 맨 위에 「받기」(zip)와 덮어쓰는 방법을 보여 준다.

## 공통 코드 고치기

`client/` 의 원본을 고친 뒤 **`sync-clients.bat`** — 모든 앱 프로젝트에 다시 복사합니다 (앱 목록: `tools/apps.ps1`).

| 파일 | 하는 일 |
|---|---|
| `init.bat` | 처음 한 번 — 공개 저장소 만들고 올리기 |
| `sync-clients.bat` | 공통 업데이터 코드를 모든 앱에 복사 |
| `tools/release-android.ps1` | 안드로이드 릴리스 (각 앱의 `release.bat` 이 부른다) |
| `tools/release-windows.ps1` | 윈도우 릴리스 (각 앱의 `release.bat` 이 부른다) |
| `tools/release-capacitor.ps1` | Capacitor 앱 릴리스 |
| `tools/release-zip.ps1` | HTML 앱 · 크롬 확장 릴리스 (zip) |
| `tools/common.ps1` | 릴리스 · manifest 공통 |
