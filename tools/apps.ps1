# 릴리스 저장소를 쓰는 앱 목록. 새 앱을 붙이면 여기에 한 줄 추가하고 9-1_공통업데이터복사.bat 을 실행한다.
#   Key     : 릴리스 태그 · manifest 이름 (소문자)
#   Folder  : repos 아래 프로젝트 폴더
#   Package : (안드로이드) 패키지 — AppUpdater.kt 가 <Package>.update 로 들어간다
#   Target  : (윈도우) AppUpdater.cs 를 둘 위치 (프로젝트 폴더 기준)
$AndroidApps = @(
    @{ Key = 'subsyncmobile'; Folder = 'SubSyncMobile'; Package = 'com.coarsoft.subsyncmobile'; Name = '싱크 스튜디오 모바일' },
    @{ Key = 'midrepeat';     Folder = 'MidRepeat';     Package = 'com.coarsoft.midrepeat';     Name = '따라말해' },
    @{ Key = 'autoclicker';   Folder = 'AutoClicker';   Package = 'com.coarsoft.autoclicker';   Name = '오토클릭' },
    @{ Key = 'instaget';      Folder = 'InstaGet';      Package = 'com.coarsoft.instaget';      Name = '인스타 받기' }
)
$WindowsApps = @(
    @{ Key = 'subsyncstudio';    Folder = 'SubSyncStudio';      Target = 'src\SubSyncStudio\Services\AppUpdater.cs';   Name = '싱크 스튜디오' },
    @{ Key = 'middictation';     Folder = 'MidDictation';       Target = 'src\MidDictation\Services\AppUpdater.cs';    Name = '받아쓰기 스튜디오' },
    @{ Key = 'bookreviewstudio'; Folder = 'BookReviewStudio';   Target = 'BookReviewStudio\AppUpdater.cs';             Name = '서평 스튜디오' },
    @{ Key = 'mkvbatchmerger';   Folder = 'MkvBatchMerger';     Target = 'src\MkvBatchMerger\Services\AppUpdater.cs';  Name = 'MKV 일괄 병합기' },
    @{ Key = 'mediarenamer';     Folder = 'files-Naming-rules'; Target = 'AppUpdater.cs';                              Name = '파일 이름 규칙' }
)
# Capacitor(웹앱 + 안드로이드, Java) — AppUpdater.java · UpdateReceiver.java 가 <Package>.update 로
$JavaApps = @(
    @{ Key = 'apptech';       Folder = 'apptech-app';          Package = 'com.apptech.checker';       Name = '앱테크 체크' },
    @{ Key = 'bookreviewapp'; Folder = 'bookReview-app';       Package = 'com.coarsoft.bookreview';   Name = '도서 서평 관리' },
    @{ Key = 'tagcopy';       Folder = 'tossQuiz-app';         Package = 'com.coarsoft.tagcopy';      Name = '태그 복사' },
    @{ Key = 'riichiguide';   Folder = 'riichi-mahjong-guide'; Package = 'com.coarsoft.riichiscorer'; Name = '리치 마작 가이드' }
)
# 폴더째 배포하는 HTML 앱 — update.ps1 이 프로젝트 폴더로
$WebApps = @(
    @{ Key = 'nobunaga16'; Folder = 'nobunaga-manual'; Name = '신장의 야망 16 한자 매뉴얼' }
)
# 크롬 확장 — update-check.js 가 프로젝트 폴더로 (새 버전 알림까지)
$ChromeApps = @(
    @{ Key = 'commentcopier'; Folder = 'comment-copier';       Name = '댓글 문구 순서 복사기' },
    @{ Key = 'urlparser';     Folder = 'url-parser-extension'; Name = '네이버 페이 URL 파서' }
)
