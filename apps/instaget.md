# 인스타 받기

## ⬇ [InstaGet-0.1.0.apk 받기](https://github.com/tohinata/app-releases/releases/download/instaget-v0.1.0/InstaGet-0.1.0.apk)

안드로이드 · 버전 **0.1.0** · 5.8MB · 2026-10-14

폰에서 이 페이지를 열고 위 링크를 누르면 APK 를 받습니다. 받은 파일을 열어 설치하세요.

- 처음 한 번 「출처를 알 수 없는 앱 설치」 허용이 필요합니다.
- 한 번 설치하면 그다음부터는 앱이 알아서 새 버전을 확인하고 업데이트합니다.

## 바뀐 점 (0.1.0)

처음 만든 버전.

### 기능
- 인스타그램 링크(게시물 · 릴스 · IGTV · 스토리 · 하이라이트 · 프로필)를 넣으면 사진 · 동영상 목록을 보여 주고 골라서 저장
- 붙여넣기 버튼, 복사한 링크 자동 붙여넣기, 인스타 앱의 공유 → 인스타 받기
- 여러 장 게시물: 전부 받기 / 골라 받기 / 한 장만 받기
- 스토리 · 하이라이트 · 비공개 계정은 앱 안에서 인스타 로그인 (공식 로그인 페이지, WebView)
- 프로필 사진 원본 크기 (로그인 시 HD)
- 캡션 복사, 인스타에서 원본 열기
- DownloadManager 로 저장 — 사진 Pictures/InstaGet, 동영상 Movies/InstaGet, 알림창 진행률
- 받은 파일 화면: 사진/동영상 필터, 열기 · 공유 · 원본 보기 · 삭제, 실패 항목 정리
- 이미 받은 파일 건너뛰기, 가져오면 바로 전부 받기 (설정)
- 앱 정보 · 수정 이력 화면
- 광고 없음

### 가져오는 방식
- 게시물: (로그인 시) 앱 API → 웹 GraphQL → 임베드 페이지 → og 메타 순서로 시도
- 스토리 · 하이라이트: api/v1/feed/reels_media
- 프로필: api/v1/users/web_profile_info (+ 로그인 시 users/<id>/info 의 HD 사진)

### 배치 파일
- install.bat, install-nostream.bat, build-apk.bat, commit.bat, push.bat (따라말해와 같은 방식)

## 이전 버전

| 버전 | 날짜 |
|---|---|
| [0.1.0 apptech-v1.13.0 riichiguide-v1.4.3 subsyncstudio-v0.1.1 autoclicker-v1.11.0 mkvbatchmerger-v1.0.0 midrepeat-v0.12.0 middictation-v0.9.1 subsyncmobile-v0.1.1 subsyncmobile-v0.1.0](https://github.com/tohinata/app-releases/releases/tag/instaget-v0.1.0 apptech-v1.13.0 riichiguide-v1.4.3 subsyncstudio-v0.1.1 autoclicker-v1.11.0 mkvbatchmerger-v1.0.0 midrepeat-v0.12.0 middictation-v0.9.1 subsyncmobile-v0.1.1 subsyncmobile-v0.1.0) | 2026-10-14 |

---
[← 전체 앱 목록](../README.md)
