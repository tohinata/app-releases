/*
 * 공통 새 버전 알림 (크롬 확장).
 *
 * 원본: app-releases/client/chrome/update-check.js — 고칠 때는 원본을 고치고
 * app-releases/sync-clients.bat 으로 모든 확장에 다시 복사한다.
 *
 * 압축 해제로 설치한 확장은 크롬이 스스로 바꿔 넣지 못한다. 그래서 새 버전을 확인해
 * 아이콘에 NEW 를 띄우고, 팝업 맨 위에 「받기」 안내를 보여 주는 데까지 한다.
 *
 *   background.js 맨 위:  importScripts("update-check.js");
 *   popup.html:           <script src="update-check.js"></script>  (팝업 스크립트보다 먼저)
 *
 * 권한: storage (이미 있음). raw.githubusercontent.com 은 CORS 를 허용해 host 권한이 필요 없다.
 */
(function (root) {
  "use strict";

  const APP_KEY = "__APP__";
  const MANIFEST = "https://raw.githubusercontent.com/tohinata/app-releases/main/manifest/" + APP_KEY + ".json";
  const STORE_KEY = "__coarUpdate";

  function current() {
    return chrome.runtime.getManifest().version;
  }

  /** "1.2" < "1.10.0" 처럼 숫자로 비교 */
  function newer(a, b) {
    const pa = String(a).split(".").map((x) => parseInt(x, 10) || 0);
    const pb = String(b).split(".").map((x) => parseInt(x, 10) || 0);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
      const d = (pa[i] || 0) - (pb[i] || 0);
      if (d !== 0) return d > 0;
    }
    return false;
  }

  async function check() {
    try {
      const res = await fetch(MANIFEST + "?t=" + Math.floor(Date.now() / 60000), { cache: "no-store" });
      if (!res.ok) return null;
      const info = JSON.parse((await res.text()).replace(/^\uFEFF/, ""));
      if (info && info.version && newer(info.version, current())) {
        await chrome.storage.local.set({ [STORE_KEY]: { version: info.version, url: info.url, notes: info.notes || "" } });
        try {
          await chrome.action.setBadgeText({ text: "NEW" });
          await chrome.action.setBadgeBackgroundColor({ color: "#26A69A" });
        } catch (e) {}
        return info;
      }
      await chrome.storage.local.remove(STORE_KEY);
      try { await chrome.action.setBadgeText({ text: "" }); } catch (e) {}
      return null;
    } catch (e) {
      return null; // 인터넷이 없으면 조용히 넘어간다
    }
  }

  /** 팝업 맨 위에 새 버전 안내 */
  async function renderBanner() {
    const s = await chrome.storage.local.get(STORE_KEY);
    const info = s[STORE_KEY];
    if (!info || !newer(info.version, current())) return;
    if (document.getElementById("coar-update")) return;

    const box = document.createElement("div");
    box.id = "coar-update";
    box.style.cssText =
      "margin:0 0 8px;padding:8px 10px;border-radius:8px;background:#E0F2F1;color:#00695C;" +
      "font:12px/1.5 system-ui,sans-serif;border:1px solid #80CBC4";
    const title = document.createElement("div");
    title.style.fontWeight = "700";
    title.textContent = "새 버전 " + info.version + " (지금 " + current() + ")";
    const how = document.createElement("div");
    how.textContent = "받은 zip 을 풀어 지금 확장 폴더에 덮어쓴 뒤, chrome://extensions 에서 새로고침(⟳)을 누르세요.";
    const btn = document.createElement("button");
    btn.textContent = "받기";
    btn.style.cssText = "margin-top:6px;padding:3px 12px;border:0;border-radius:6px;background:#26A69A;color:#fff;cursor:pointer";
    btn.addEventListener("click", () => chrome.tabs.create({ url: info.url }));
    box.append(title, how, btn);
    document.body.prepend(box);
  }

  root.CoarUpdate = { check, renderBanner };

  if (typeof document === "undefined") {
    // 서비스 워커: 크롬을 켤 때 · 확장을 설치/갱신할 때 확인
    chrome.runtime.onStartup.addListener(() => { check(); });
    chrome.runtime.onInstalled.addListener(() => { check(); });
  } else {
    // 팝업: 저장된 안내를 바로 보여 주고, 한 번 더 확인
    const run = () => { renderBanner(); check().then(() => renderBanner()); };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  }
})(typeof self !== "undefined" ? self : this);
