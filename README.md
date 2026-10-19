# 百米賽跑・裁判台（Flutter Host）

Host（裁判）手機／平板跑這個 App，畫面可投影。選手不用裝 App：掃 QR → 瀏覽器開啟選手頁 → 回傳陀螺儀與震動（線性加速度）。

## 建專案並打包 APK
```bash
flutter create --org com.example --project-name race_referee race_referee_app
cd race_referee_app
# 把這個資料夾的 pubspec.yaml 與 lib/ 整個覆蓋過去
flutter pub get
```
編輯 `android/app/src/main/AndroidManifest.xml`，在 `<application` 之前加入：
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
```
（release 版預設沒有 INTERNET 權限，沒加的話伺服器開不起來。）
```bash
flutter run                 # 接手機測試
flutter build apk --release # 輸出 build/app/outputs/flutter-apk/app-release.apk
```

## 使用流程
1. Host 與選手手機連同一個 Wi-Fi，或選手連 Host 的行動熱點（沒有路由器時用）。
2. 選手掃 QR → 瀏覽器警告「連線不安全」→ 進階 → 繼續前往 → 輸入名字 → 按「連線並啟用感測器」。
3. 前兩位連線的是 A／B 道，其餘為觀戰（可按 ✕ 移除讓候補遞補、或「交換跑道」）。
4. 賽前面板：看每人原始訊號曲線，調「來源／靈敏度／死區」，或按「靜止校準」自動設死區。
5. 按「開始比賽」→ 倒數 3 秒（有支援的手機會震動）→ 揮手機跑 100 公尺。

## 訊號 → 速度
- 陀螺儀 ÷ 720°/s、震動 ÷ 30 m/s² → 0..1（可選陀螺儀／震動／兩者取大）
- 取 0.3 秒衰減的峰值包絡（揮手是來回擺動，不取包絡會一抖一停）
- (包絡 − 死區) ÷ (1 − 死區) × 靈敏度 × 8 m/s，上限 12 m/s，再平滑追上目標速度
- 搶跑無效：倒數結束前不計距離

## 用 GitHub 自動打包與安裝頁（不用裝 Flutter）
推到 `main` 後，`.github/workflows/build.yml` 會自動：
- 打包 Android APK、Windows 安裝程式（內含 VC++ 執行庫並自動加入防火牆規則）與免安裝 zip
- 建立 Release（固定下載網址 `releases/latest/download/檔名`）
- 把 `docs/` 部署成安裝頁：自動偵測 Android／Windows 並顯示對應下載與步驟，偵測不到或想裝別的平台時可自己選

**只需設定一次**：repo → Settings → Pages → Source 選 **GitHub Actions**。
安裝頁網址：`https://<帳號>.github.io/<repo 名稱>/`，把它（或做成 QR）給要當 Host 的人即可。
若 repo 是 private，匿名下載連結不會通；請設為 public，或用 Release 頁面登入下載。
