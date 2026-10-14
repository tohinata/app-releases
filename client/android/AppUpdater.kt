package __PACKAGE__.update

import android.app.Activity
import android.app.AlertDialog
import android.app.Application
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 공통 앱 업데이터 (안드로이드).
 *
 * 원본: app-releases/client/android/AppUpdater.kt — 고칠 때는 원본을 고치고
 * app-releases/9-1_공통업데이터복사.bat 으로 모든 앱에 다시 복사한다.
 *
 * 공개 저장소 tohinata/app-releases 의 manifest/<앱키>.json 을 읽어
 * 지금보다 versionCode 가 크면 「업데이트」를 묻고, APK 를 받아 확인(SHA-256 · 패키지 이름)한 뒤
 * 안드로이드 설치 창을 띄운다. AndroidX 없이 프레임워크 API 만 쓴다.
 *
 * 필요한 것 (AndroidManifest.xml):
 *   <uses-permission android:name="android.permission.INTERNET" />
 *   <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
 *   <uses-permission android:name="android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION" />
 *   <receiver android:name=".update.UpdateReceiver" android:exported="false" />
 */
object AppUpdater {

    private const val MANIFEST = "https://raw.githubusercontent.com/tohinata/app-releases/main/manifest/%s.json"

    private var checkedThisRun = false
    private val main = Handler(Looper.getMainLooper())

    class Info(
        val versionCode: Long,
        val versionName: String,
        val url: String,
        val sha256: String,
        val size: Long,
        val notes: String
    )

    /**
     * 앱 실행 때 (MainActivity.onCreate). 프로세스마다 한 번만 확인한다 — 화면 회전으로 다시 불려도 괜찮다.
     * 최신이거나 인터넷이 안 되면 아무것도 보이지 않는다.
     */
    fun checkOnLaunch(activity: Activity, appKey: String) {
        track(activity)
        if (checkedThisRun) return
        checkedThisRun = true
        reportUpdated(activity)
        check(activity, appKey, manual = false)
    }

    /** 「업데이트 확인」을 눌렀을 때. 결과를 항상 알려 준다. */
    fun checkNow(activity: Activity, appKey: String) {
        track(activity)
        toast(activity, "업데이트 확인 중…")
        check(activity, appKey, manual = true)
    }

    // ---------------------------------------------------------------- 앞에 떠 있는 화면 추적
    // 설치 확인 창은 앞에 떠 있는 화면에서 띄워야 한다 (백그라운드에서 띄우면 안드로이드가 조용히 막는다).
    // 그 사이 다른 앱으로 갔으면 돌아왔을 때 띄운다.

    private var tracking = false
    private var resumed: WeakReference<Activity>? = null
    private var pendingConfirm: Intent? = null

    private fun track(activity: Activity) {
        resumed = WeakReference(activity)
        if (tracking) return
        tracking = true
        activity.application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(a: Activity) {
                resumed = WeakReference(a)
                pendingConfirm?.let { pendingConfirm = null; launchConfirm(a, it) }
            }
            override fun onActivityPaused(a: Activity) {
                if (resumed?.get() === a) resumed = null
            }
            override fun onActivityCreated(a: Activity, b: Bundle?) {}
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        })
    }

    /** UpdateReceiver 가 부른다 */
    internal fun showConfirm(context: Context, confirm: Intent) {
        val a = resumed?.get()
        if (a != null && !a.isFinishing && !a.isDestroyed) launchConfirm(a, confirm)
        else pendingConfirm = confirm   // 앱으로 돌아오면 띄운다
    }

    private fun launchConfirm(a: Activity, confirm: Intent) {
        try { a.startActivity(confirm) } catch (_: Exception) { toast(a, "설치 창을 열지 못했습니다") }
    }

    private fun check(activity: Activity, appKey: String, manual: Boolean) {
        Thread {
            val info = try { fetch(appKey) } catch (_: Exception) { null }
            main.post {
                if (activity.isFinishing || activity.isDestroyed) return@post
                val current = currentVersionCode(activity)
                when {
                    info == null ->
                        if (manual) toast(activity, "업데이트 정보를 받지 못했습니다. 인터넷 연결을 확인하세요.")
                    info.versionCode <= current ->
                        if (manual) toast(activity, "최신 버전입니다 (${currentVersionName(activity)})")
                    else -> ask(activity, info)
                }
            }
        }.start()
    }

    private fun fetch(appKey: String): Info? {
        // raw.githubusercontent.com 은 몇 분 캐시한다. 1분 단위 쿼리로 너무 오래된 값을 피한다.
        val url = MANIFEST.format(appKey) + "?t=" + System.currentTimeMillis() / 60_000
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 8000
            readTimeout = 8000
            setRequestProperty("User-Agent", "coarsoft-updater")
        }
        try {
            if (c.responseCode != 200) return null
            val text = c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }.trimStart('﻿')
            val o = JSONObject(text)
            return Info(
                versionCode = o.getLong("versionCode"),
                versionName = o.getString("version"),
                url = o.getString("url"),
                sha256 = o.optString("sha256"),
                size = o.optLong("size"),
                notes = o.optString("notes")
            )
        } finally {
            c.disconnect()
        }
    }

    // ================================================================ 묻기 · 받기

    private fun ask(activity: Activity, info: Info) {
        val sizeMb = if (info.size > 0) " · %.1fMB".format(info.size / 1048576.0) else ""
        val notes = info.notes.trim().let { if (it.length > 1500) it.take(1500) + "…" else it }
        AlertDialog.Builder(activity)
            .setTitle("새 버전 ${info.versionName}")
            .setMessage("지금 ${currentVersionName(activity)} → ${info.versionName}$sizeMb" +
                if (notes.isNotEmpty()) "\n\n$notes" else "")
            .setPositiveButton("업데이트") { _, _ -> withInstallPermission(activity) { download(activity, info) } }
            .setNegativeButton("나중에", null)
            .show()
    }

    private fun download(activity: Activity, info: Info) {
        val pad = (20 * activity.resources.displayMetrics.density).toInt()
        val label = TextView(activity).apply { text = "받는 중…" }
        val bar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply { max = 1000 }
        val box = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, 0)
            addView(label)
            addView(bar)
        }
        val cancelled = AtomicBoolean(false)
        val dialog = AlertDialog.Builder(activity)
            .setTitle("업데이트 ${info.versionName}")
            .setView(box)
            .setCancelable(false)
            .setNegativeButton("취소") { _, _ -> cancelled.set(true) }
            .show()

        Thread {
            val file = File(File(activity.cacheDir, "update").apply { mkdirs() }, "update.apk")
            val error: String? = try {
                fetchFile(info.url, file, cancelled) { got, total ->
                    main.post {
                        if (total > 0) bar.progress = (got * 1000 / total).toInt()
                        label.text = "받는 중… %.1f / %.1f MB".format(got / 1048576.0, total / 1048576.0)
                    }
                }
                when {
                    cancelled.get() -> ""
                    info.sha256.isNotEmpty() && !sha256(file).equals(info.sha256, ignoreCase = true) ->
                        "받은 파일이 손상되었습니다 (SHA-256 불일치). 다시 시도하세요."
                    else -> null
                }
            } catch (e: Exception) {
                if (cancelled.get()) "" else "받지 못했습니다: ${e.message}"
            }
            main.post {
                try { dialog.dismiss() } catch (_: Exception) {}
                when {
                    error == null -> install(activity, file, info)
                    error.isNotEmpty() -> toast(activity.applicationContext, error)
                }
            }
        }.start()
    }

    private fun fetchFile(url: String, out: File, cancelled: AtomicBoolean, progress: (Long, Long) -> Unit) {
        var target = url
        // GitHub 릴리스 주소는 다른 호스트로 넘겨 준다 — 직접 따라간다
        repeat(5) {
            val c = (URL(target).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = false
                setRequestProperty("User-Agent", "coarsoft-updater")
            }
            try {
                val code = c.responseCode
                if (code in 300..399) {
                    target = URL(URL(target), c.getHeaderField("Location")).toString()
                    return@repeat
                }
                if (code != 200) throw IllegalStateException("HTTP $code")
                val total = c.contentLengthLong
                var got = 0L
                var last = 0L
                c.inputStream.use { input ->
                    out.outputStream().use { o ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            if (cancelled.get()) return
                            val n = input.read(buf)
                            if (n < 0) break
                            o.write(buf, 0, n)
                            got += n
                            val now = System.currentTimeMillis()
                            if (now - last > 120) { last = now; progress(got, total) }
                        }
                    }
                }
                progress(got, total)
                return
            } finally {
                c.disconnect()
            }
        }
        throw IllegalStateException("주소를 너무 많이 넘겨받았습니다")
    }

    // ================================================================ 설치

    /**
     * 「출처를 알 수 없는 앱 설치」 허용 확인 — 받기 전에 묻는다.
     * (안드로이드 11 은 허용을 켜면 앱을 다시 시작하므로, 받은 뒤에 물으면 받은 것이 버려진다.
     *  다시 시작돼도 checkOnLaunch 가 다시 확인해 이어서 묻는다.)
     */
    private fun withInstallPermission(activity: Activity, then: () -> Unit) {
        if (activity.packageManager.canRequestPackageInstalls()) { then(); return }
        if (activity.isFinishing || activity.isDestroyed) return
        AlertDialog.Builder(activity)
            .setTitle("설치 허용이 필요합니다")
            .setMessage("기기마다 처음 한 번만 하면 됩니다.\n\n[설정 열기] → 「이 출처 허용」을 켜고 돌아와서 [계속]을 누르세요.")
            .setPositiveButton("계속") { _, _ -> withInstallPermission(activity, then) }
            .setNeutralButton("설정 열기") { _, _ ->
                try {
                    activity.startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
                    )
                } catch (_: Exception) {
                }
                // 돌아오면 이 창이 다시 보이게
                main.postDelayed({ withInstallPermission(activity, then) }, 500)
            }
            .setNegativeButton("취소", null)
            .show()
    }

    /** 받은 APK 를 설치 세션에 넣는다. 화면이 회전 · 종료돼도 진행되도록 앱 Context 만 쓴다. */
    private fun install(activity: Activity, file: File, info: Info) {
        val pm = activity.applicationContext.packageManager

        @Suppress("DEPRECATION")
        val archive = pm.getPackageArchiveInfo(file.path, 0)
        if (archive == null || archive.packageName != activity.packageName) {
            toast(activity.applicationContext, "받은 파일이 이 앱의 설치 파일이 아닙니다")
            return
        }

        val ctx = activity.applicationContext
        Thread {
            val installer = pm.packageInstaller
            var sessionId = -1
            try {
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(ctx.packageName)
                    // Android 12+: 이 앱이 스스로 설치한 적이 있으면 확인 창 없이 업데이트될 수 있다
                    if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
                val id = installer.createSession(params)
                sessionId = id
                main.post { showInstalling(activity, id, info.versionName) }
                installer.openSession(id).use { s ->
                    s.openWrite("app.apk", 0, file.length()).use { out ->
                        file.inputStream().use { it.copyTo(out) }
                        s.fsync(out)
                    }
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    val pi = PendingIntent.getBroadcast(
                        ctx, id, Intent(ctx, UpdateReceiver::class.java).setPackage(ctx.packageName), flags
                    )
                    // 다음 실행 때 「업데이트했습니다」를 알리려고 적어 둔다
                    ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                        .putLong("pendingCode", info.versionCode).putString("pendingName", info.versionName).apply()
                    s.commit(pi.intentSender)
                    sessionId = -1   // 커밋했으면 결과는 UpdateReceiver 가 받는다
                }
            } catch (e: Exception) {
                // 커밋 전에 실패한 세션은 버린다 (남겨 두면 기기에 쌓인다)
                if (sessionId != -1) try { installer.abandonSession(sessionId) } catch (_: Exception) {}
                main.post { hideInstalling(); toast(ctx, "설치를 시작하지 못했습니다: ${e.message}") }
            }
        }.start()
    }

    // ---------------------------------------------------------------- 설치 중 표시 · 끝난 뒤 알림
    // 설치 확인 창에서 [업데이트]를 누른 뒤에도 설치는 몇 초~수십 초 걸린다. 그동안 「설치 중」 창을 띄워 두고,
    // 설치가 끝나면 안드로이드가 이 앱을 닫는다. 다시 열면 「업데이트했습니다」를 알려 준다.

    private const val PREFS = "app_updater"
    private var installingDialog: AlertDialog? = null

    private fun showInstalling(activity: Activity, sessionId: Int, versionName: String) {
        val a = resumed?.get()?.takeIf { !it.isFinishing && !it.isDestroyed } ?: activity
        if (a.isFinishing || a.isDestroyed) return
        hideInstalling()
        val pad = (20 * a.resources.displayMetrics.density).toInt()
        val label = TextView(a).apply {
            text = "새 버전 $versionName 을(를) 설치하고 있습니다.\n\n" +
                "· 설치 확인 창이 뜨면 [업데이트]를 누르세요.\n" +
                "· 끝나면 앱이 저절로 닫힙니다. 아이콘을 눌러 다시 여세요."
        }
        val bar = ProgressBar(a, null, android.R.attr.progressBarStyleHorizontal).apply { isIndeterminate = true }
        val box = LinearLayout(a).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, 0)
            addView(label)
            addView(bar)
        }
        installingDialog = AlertDialog.Builder(a)
            .setTitle("업데이트 설치 중")
            .setView(box)
            .setCancelable(false)
            .setNegativeButton("숨기기", null)
            .show()

        val installer = a.applicationContext.packageManager.packageInstaller
        installer.registerSessionCallback(object : PackageInstaller.SessionCallback() {
            override fun onCreated(id: Int) {}
            override fun onBadgingChanged(id: Int) {}
            override fun onActiveChanged(id: Int, active: Boolean) {}
            override fun onProgressChanged(id: Int, progress: Float) {}
            override fun onFinished(id: Int, success: Boolean) {
                if (id != sessionId) return
                installer.unregisterSessionCallback(this)
                // 성공이면 곧 이 앱이 닫힌다. 취소 · 실패는 UpdateReceiver 가 알려 준다.
                if (!success) hideInstalling()
            }
        }, main)
    }

    private fun hideInstalling() {
        try { installingDialog?.dismiss() } catch (_: Exception) {}
        installingDialog = null
    }

    /** 지난번에 설치를 시작한 버전으로 바뀌었으면 알려 준다 (취소했으면 조용히 지운다) */
    private fun reportUpdated(activity: Activity) {
        val sp = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val code = sp.getLong("pendingCode", 0)
        if (code <= 0) return
        val name = sp.getString("pendingName", "") ?: ""
        sp.edit().remove("pendingCode").remove("pendingName").apply()
        if (currentVersionCode(activity) >= code) toast(activity, "새 버전 $name 으로 업데이트했습니다")
    }

    // ================================================================ 도우미

    private fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun currentVersionCode(c: Context): Long = try {
        val pi = c.packageManager.getPackageInfo(c.packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong()
    } catch (_: Exception) {
        Long.MAX_VALUE
    }

    private fun currentVersionName(c: Context): String = try {
        c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: "?"
    } catch (_: Exception) {
        "?"
    }

    private fun toast(c: Context, msg: String) = Toast.makeText(c, msg, Toast.LENGTH_LONG).show()
}

/** 설치 세션 결과. 사용자 확인이 필요하면 안드로이드 설치 창을 띄운다. */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 34) {   // 33 의 형식 지정 버전은 버그가 있다
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) AppUpdater.showConfirm(context, confirm)
            }
            PackageInstaller.STATUS_SUCCESS -> Unit   // 곧 앱이 닫힌다
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                Toast.makeText(context, "업데이트를 취소했습니다", Toast.LENGTH_SHORT).show()
            else -> {
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "코드 $status"
                Toast.makeText(context, "업데이트 설치 실패: $msg", Toast.LENGTH_LONG).show()
            }
        }
    }
}
