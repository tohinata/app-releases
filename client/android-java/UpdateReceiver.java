package __PACKAGE__.update;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;
import android.widget.Toast;

/**
 * 설치 세션 결과. 사용자 확인이 필요하면 안드로이드 설치 창을 띄운다.
 * 원본: app-releases/client/android-java/UpdateReceiver.java
 */
public class UpdateReceiver extends BroadcastReceiver {
    @Override
    @SuppressWarnings("deprecation")
    public void onReceive(Context context, Intent intent) {
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999);
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            // 33 의 형식 지정 버전은 버그가 있어 34 부터 쓴다
            Intent confirm = Build.VERSION.SDK_INT >= 34
                ? intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent.class)
                : (Intent) intent.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirm != null) AppUpdater.showConfirm(context, confirm);
        } else if (status == PackageInstaller.STATUS_SUCCESS) {
            // 새 버전으로 바뀌었다
        } else if (status == PackageInstaller.STATUS_FAILURE_ABORTED) {
            Toast.makeText(context, "업데이트를 취소했습니다", Toast.LENGTH_SHORT).show();
        } else {
            String msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
            Toast.makeText(context, "업데이트 설치 실패: " + (msg != null ? msg : "코드 " + status), Toast.LENGTH_LONG).show();
        }
    }
}
