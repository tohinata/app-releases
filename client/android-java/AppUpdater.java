package __PACKAGE__.update;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Application;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.ref.WeakReference;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * 공통 앱 업데이터 (안드로이드 · Java 판 — Capacitor 앱용).
 *
 * 원본: app-releases/client/android-java/AppUpdater.java — 고칠 때는 원본을 고치고
 * app-releases/9-1_공통업데이터복사.bat 으로 모든 앱에 다시 복사한다. Kotlin 판(client/android)과 동작이 같다.
 *
 * 공개 저장소 tohinata/app-releases 의 manifest/<앱키>.json 을 읽어 지금보다 versionCode 가 크면
 * 「업데이트」를 묻고, APK 를 받아 확인(SHA-256 · 패키지 이름)한 뒤 안드로이드 설치 창을 띄운다.
 *
 * 필요한 것 (AndroidManifest.xml):
 *   INTERNET, REQUEST_INSTALL_PACKAGES, UPDATE_PACKAGES_WITHOUT_USER_ACTION 권한
 *   <receiver android:name=".update.UpdateReceiver" android:exported="false" />
 */
public final class AppUpdater {

    private static final String MANIFEST = "https://raw.githubusercontent.com/tohinata/app-releases/main/manifest/%s.json";

    private static boolean checkedThisRun = false;
    private static final Handler main = new Handler(Looper.getMainLooper());

    private AppUpdater() {}

    static final class Info {
        long versionCode;
        String versionName;
        String url;
        String sha256;
        long size;
        String notes;
    }

    /** 앱 실행 때 (MainActivity.onCreate). 프로세스마다 한 번만 확인한다. 최신이거나 인터넷이 안 되면 조용히 넘어간다. */
    public static void checkOnLaunch(Activity activity, String appKey) {
        track(activity);
        if (checkedThisRun) return;
        checkedThisRun = true;
        reportUpdated(activity);
        check(activity, appKey, false);
    }

    /** 「업데이트 확인」을 눌렀을 때. 결과를 항상 알려 준다. */
    public static void checkNow(Activity activity, String appKey) {
        track(activity);
        toast(activity, "업데이트 확인 중…");
        check(activity, appKey, true);
    }

    // ---------------------------------------------------------------- 앞에 떠 있는 화면 추적
    // 설치 확인 창은 앞에 떠 있는 화면에서 띄워야 한다. 그 사이 다른 앱으로 갔으면 돌아왔을 때 띄운다.

    private static boolean tracking = false;
    private static WeakReference<Activity> resumed;
    private static Intent pendingConfirm;

    private static void track(Activity activity) {
        resumed = new WeakReference<>(activity);
        if (tracking) return;
        tracking = true;
        activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityResumed(Activity a) {
                resumed = new WeakReference<>(a);
                if (pendingConfirm != null) {
                    Intent c = pendingConfirm;
                    pendingConfirm = null;
                    launchConfirm(a, c);
                }
            }
            @Override public void onActivityPaused(Activity a) {
                if (resumed != null && resumed.get() == a) resumed = null;
            }
            @Override public void onActivityCreated(Activity a, Bundle b) {}
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
            @Override public void onActivityDestroyed(Activity a) {}
        });
    }

    /** UpdateReceiver 가 부른다 */
    static void showConfirm(Context context, Intent confirm) {
        Activity a = resumed == null ? null : resumed.get();
        if (a != null && !a.isFinishing() && !a.isDestroyed()) launchConfirm(a, confirm);
        else pendingConfirm = confirm;
    }

    private static void launchConfirm(Activity a, Intent confirm) {
        try {
            a.startActivity(confirm);
        } catch (Exception e) {
            toast(a, "설치 창을 열지 못했습니다");
        }
    }

    private static void check(final Activity activity, final String appKey, final boolean manual) {
        new Thread(() -> {
            Info info;
            try {
                info = fetch(appKey);
            } catch (Exception e) {
                info = null;
            }
            final Info result = info;
            main.post(() -> {
                if (activity.isFinishing() || activity.isDestroyed()) return;
                long current = currentVersionCode(activity);
                if (result == null) {
                    if (manual) toast(activity, "업데이트 정보를 받지 못했습니다. 인터넷 연결을 확인하세요.");
                } else if (result.versionCode <= current) {
                    if (manual) toast(activity, "최신 버전입니다 (" + currentVersionName(activity) + ")");
                } else {
                    ask(activity, result);
                }
            });
        }).start();
    }

    private static Info fetch(String appKey) throws Exception {
        String url = String.format(Locale.ROOT, MANIFEST, appKey) + "?t=" + (System.currentTimeMillis() / 60_000);
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(8000);
        c.setReadTimeout(8000);
        c.setRequestProperty("User-Agent", "coarsoft-updater");
        try {
            if (c.getResponseCode() != 200) return null;
            String text;
            try (InputStream in = c.getInputStream()) {
                text = readAll(in);
            }
            if (text.startsWith("\uFEFF")) text = text.substring(1);
            JSONObject o = new JSONObject(text);
            Info i = new Info();
            i.versionCode = o.getLong("versionCode");
            i.versionName = o.getString("version");
            i.url = o.getString("url");
            i.sha256 = o.optString("sha256");
            i.size = o.optLong("size");
            i.notes = o.optString("notes");
            return i;
        } finally {
            c.disconnect();
        }
    }

    // ================================================================ 묻기 · 받기

    private static void ask(final Activity activity, final Info info) {
        String sizeMb = info.size > 0 ? String.format(Locale.ROOT, " · %.1fMB", info.size / 1048576.0) : "";
        String notes = info.notes == null ? "" : info.notes.trim();
        if (notes.length() > 1500) notes = notes.substring(0, 1500) + "…";
        new AlertDialog.Builder(activity)
            .setTitle("새 버전 " + info.versionName)
            .setMessage("지금 " + currentVersionName(activity) + " → " + info.versionName + sizeMb
                + (notes.isEmpty() ? "" : "\n\n" + notes))
            .setPositiveButton("업데이트", (d, w) -> withInstallPermission(activity, () -> download(activity, info)))
            .setNegativeButton("나중에", null)
            .show();
    }

    private static void download(final Activity activity, final Info info) {
        int pad = (int) (20 * activity.getResources().getDisplayMetrics().density);
        final TextView label = new TextView(activity);
        label.setText("받는 중…");
        final ProgressBar bar = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(1000);
        LinearLayout box = new LinearLayout(activity);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(pad, pad / 2, pad, 0);
        box.addView(label);
        box.addView(bar);
        final AtomicBoolean cancelled = new AtomicBoolean(false);
        final AlertDialog dialog = new AlertDialog.Builder(activity)
            .setTitle("업데이트 " + info.versionName)
            .setView(box)
            .setCancelable(false)
            .setNegativeButton("취소", (d, w) -> cancelled.set(true))
            .show();

        final Context app = activity.getApplicationContext();
        new Thread(() -> {
            File dir = new File(activity.getCacheDir(), "update");
            dir.mkdirs();
            final File file = new File(dir, "update.apk");
            String error;
            try {
                fetchFile(info.url, file, cancelled, (got, total) -> main.post(() -> {
                    if (total > 0) bar.setProgress((int) (got * 1000 / total));
                    label.setText(String.format(Locale.ROOT, "받는 중… %.1f / %.1f MB", got / 1048576.0, total / 1048576.0));
                }));
                if (cancelled.get()) error = "";
                else if (info.sha256 != null && !info.sha256.isEmpty() && !sha256(file).equalsIgnoreCase(info.sha256))
                    error = "받은 파일이 손상되었습니다 (SHA-256 불일치). 다시 시도하세요.";
                else error = null;
            } catch (Exception e) {
                error = cancelled.get() ? "" : "받지 못했습니다: " + e.getMessage();
            }
            final String err = error;
            main.post(() -> {
                try { dialog.dismiss(); } catch (Exception ignored) {}
                if (err == null) install(activity, file, info);
                else if (!err.isEmpty()) toast(app, err);
            });
        }).start();
    }

    interface Progress { void on(long got, long total); }

    private static void fetchFile(String url, File out, AtomicBoolean cancelled, Progress progress) throws Exception {
        String target = url;
        // GitHub 릴리스 주소는 다른 호스트로 넘겨 준다 — 직접 따라간다
        for (int hop = 0; hop < 5; hop++) {
            HttpURLConnection c = (HttpURLConnection) new URL(target).openConnection();
            c.setConnectTimeout(15_000);
            c.setReadTimeout(30_000);
            c.setInstanceFollowRedirects(false);
            c.setRequestProperty("User-Agent", "coarsoft-updater");
            try {
                int code = c.getResponseCode();
                if (code >= 300 && code < 400) {
                    target = new URL(new URL(target), c.getHeaderField("Location")).toString();
                    continue;
                }
                if (code != 200) throw new IllegalStateException("HTTP " + code);
                long total = c.getContentLength();   // (Long 판은 API 24 부터)
                long got = 0, last = 0;
                try (InputStream in = c.getInputStream(); OutputStream o = new FileOutputStream(out)) {
                    byte[] buf = new byte[64 * 1024];
                    int n;
                    while ((n = in.read(buf)) >= 0) {
                        if (cancelled.get()) return;
                        o.write(buf, 0, n);
                        got += n;
                        long now = System.currentTimeMillis();
                        if (now - last > 120) { last = now; progress.on(got, total); }
                    }
                }
                progress.on(got, total);
                return;
            } finally {
                c.disconnect();
            }
        }
        throw new IllegalStateException("주소를 너무 많이 넘겨받았습니다");
    }

    // ================================================================ 설치

    /** 「출처를 알 수 없는 앱 설치」 허용 — 받기 전에 묻는다 (안드로이드 11 은 허용하면 앱을 다시 시작한다). */
    private static void withInstallPermission(final Activity activity, final Runnable then) {
        if (Build.VERSION.SDK_INT < 26 || activity.getPackageManager().canRequestPackageInstalls()) {
            then.run();
            return;
        }
        if (activity.isFinishing() || activity.isDestroyed()) return;
        new AlertDialog.Builder(activity)
            .setTitle("설치 허용이 필요합니다")
            .setMessage("기기마다 처음 한 번만 하면 됩니다.\n\n[설정 열기] → 「이 출처 허용」을 켜고 돌아와서 [계속]을 누르세요.")
            .setPositiveButton("계속", (d, w) -> withInstallPermission(activity, then))
            .setNeutralButton("설정 열기", (d, w) -> {
                try {
                    activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + activity.getPackageName())));
                } catch (Exception ignored) {
                }
                main.postDelayed(() -> withInstallPermission(activity, then), 500);
            })
            .setNegativeButton("취소", null)
            .show();
    }

    /** 받은 APK 를 설치 세션에 넣는다. 화면이 회전 · 종료돼도 진행되도록 앱 Context 만 쓴다. */
    private static void install(final Activity activity, final File file, final Info info) {
        final Context ctx = activity.getApplicationContext();
        final PackageManager pm = ctx.getPackageManager();
        PackageInfo archive = pm.getPackageArchiveInfo(file.getPath(), 0);
        if (archive == null || !ctx.getPackageName().equals(archive.packageName)) {
            toast(ctx, "받은 파일이 이 앱의 설치 파일이 아닙니다");
            return;
        }
        new Thread(() -> {
            final PackageInstaller installer = pm.getPackageInstaller();
            int sessionId = -1;
            try {
                PackageInstaller.SessionParams params =
                    new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
                params.setAppPackageName(ctx.getPackageName());
                // Android 12+: 이 앱이 스스로 설치한 적이 있으면 확인 창 없이 업데이트될 수 있다
                if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
                final int id = installer.createSession(params);
                sessionId = id;
                main.post(() -> showInstalling(activity, id, info.versionName));
                try (PackageInstaller.Session s = installer.openSession(id)) {
                    try (OutputStream out = s.openWrite("app.apk", 0, file.length());
                         InputStream in = new FileInputStream(file)) {
                        byte[] buf = new byte[64 * 1024];
                        int n;
                        while ((n = in.read(buf)) >= 0) out.write(buf, 0, n);
                        s.fsync(out);
                    }
                    int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
                    Intent i = new Intent(ctx, UpdateReceiver.class).setPackage(ctx.getPackageName());
                    PendingIntent pi = PendingIntent.getBroadcast(ctx, id, i, flags);
                    // 다음 실행 때 「업데이트했습니다」를 알리려고 적어 둔다
                    ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putLong("pendingCode", info.versionCode).putString("pendingName", info.versionName).apply();
                    s.commit(pi.getIntentSender());
                    sessionId = -1;   // 커밋했으면 결과는 UpdateReceiver 가 받는다
                }
            } catch (Exception e) {
                // 커밋 전에 실패한 세션은 버린다 (남겨 두면 기기에 쌓인다)
                if (sessionId != -1) {
                    try { installer.abandonSession(sessionId); } catch (Exception ignored) {}
                }
                main.post(() -> { hideInstalling(); toast(ctx, "설치를 시작하지 못했습니다: " + e.getMessage()); });
            }
        }).start();
    }

    // ---------------------------------------------------------------- 설치 중 표시 · 끝난 뒤 알림
    // 설치 확인 창에서 [업데이트]를 누른 뒤에도 설치는 몇 초~수십 초 걸린다. 그동안 「설치 중」 창을 띄워 두고,
    // 설치가 끝나면 안드로이드가 이 앱을 닫는다. 다시 열면 「업데이트했습니다」를 알려 준다.

    private static final String PREFS = "app_updater";
    private static AlertDialog installingDialog;

    private static void showInstalling(Activity activity, final int sessionId, String versionName) {
        Activity a = resumed == null ? null : resumed.get();
        if (a == null || a.isFinishing() || a.isDestroyed()) a = activity;
        if (a.isFinishing() || a.isDestroyed()) return;
        hideInstalling();
        int pad = (int) (20 * a.getResources().getDisplayMetrics().density);
        TextView label = new TextView(a);
        label.setText("새 버전 " + versionName + " 을(를) 설치하고 있습니다.\n\n"
            + "· 설치 확인 창이 뜨면 [업데이트]를 누르세요.\n"
            + "· 끝나면 앱이 저절로 닫힙니다. 아이콘을 눌러 다시 여세요.");
        ProgressBar bar = new ProgressBar(a, null, android.R.attr.progressBarStyleHorizontal);
        bar.setIndeterminate(true);
        LinearLayout box = new LinearLayout(a);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(pad, pad / 2, pad, 0);
        box.addView(label);
        box.addView(bar);
        installingDialog = new AlertDialog.Builder(a)
            .setTitle("업데이트 설치 중")
            .setView(box)
            .setCancelable(false)
            .setNegativeButton("숨기기", null)
            .show();

        final PackageInstaller installer = a.getApplicationContext().getPackageManager().getPackageInstaller();
        installer.registerSessionCallback(new PackageInstaller.SessionCallback() {
            @Override public void onCreated(int id) {}
            @Override public void onBadgingChanged(int id) {}
            @Override public void onActiveChanged(int id, boolean active) {}
            @Override public void onProgressChanged(int id, float progress) {}
            @Override public void onFinished(int id, boolean success) {
                if (id != sessionId) return;
                installer.unregisterSessionCallback(this);
                // 성공이면 곧 이 앱이 닫힌다. 취소 · 실패는 UpdateReceiver 가 알려 준다.
                if (!success) hideInstalling();
            }
        }, main);
    }

    private static void hideInstalling() {
        try { if (installingDialog != null) installingDialog.dismiss(); } catch (Exception ignored) {}
        installingDialog = null;
    }

    /** 지난번에 설치를 시작한 버전으로 바뀌었으면 알려 준다 (취소했으면 조용히 지운다) */
    private static void reportUpdated(Activity activity) {
        android.content.SharedPreferences sp = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long code = sp.getLong("pendingCode", 0);
        if (code <= 0) return;
        String name = sp.getString("pendingName", "");
        sp.edit().remove("pendingCode").remove("pendingName").apply();
        if (currentVersionCode(activity) >= code) toast(activity, "새 버전 " + name + " 으로 업데이트했습니다");
    }

    // ================================================================ 도우미

    private static String readAll(InputStream in) throws Exception {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) >= 0) b.write(buf, 0, n);
        return new String(b.toByteArray(), StandardCharsets.UTF_8);
    }

    private static String sha256(File file) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) {
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = in.read(buf)) >= 0) md.update(buf, 0, n);
        }
        StringBuilder sb = new StringBuilder();
        for (byte x : md.digest()) sb.append(String.format(Locale.ROOT, "%02x", x));
        return sb.toString();
    }

    @SuppressWarnings("deprecation")
    private static long currentVersionCode(Context c) {
        try {
            PackageInfo pi = c.getPackageManager().getPackageInfo(c.getPackageName(), 0);
            return Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
        } catch (Exception e) {
            return Long.MAX_VALUE;
        }
    }

    private static String currentVersionName(Context c) {
        try {
            String v = c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName;
            return v == null ? "?" : v;
        } catch (Exception e) {
            return "?";
        }
    }

    private static void toast(Context c, String msg) {
        Toast.makeText(c, msg, Toast.LENGTH_LONG).show();
    }
}
