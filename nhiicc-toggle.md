# nhiicc-toggle.sh — 健保卡元件開關

啟動 / 停止 macOS 上的健保卡網路服務元件 (mNHIICC)。

這個元件由健保署官方簽章（Team ID `NRMY799KE6`），是合法程式，但常駐時很吃 CPU。
沒在用健保卡讀卡機時可以關掉，要刷健保卡時再開。

## 安裝（加執行權限，一次就好）

```bash
chmod +x ~/projects/scripts/nhiicc-toggle.sh
```

## 用法

```bash
# 看狀態（不需 sudo）
~/projects/scripts/nhiicc-toggle.sh status

# 關掉（省 CPU）
sudo ~/projects/scripts/nhiicc-toggle.sh stop

# 要用健保卡時再開
sudo ~/projects/scripts/nhiicc-toggle.sh start

# 重啟
sudo ~/projects/scripts/nhiicc-toggle.sh restart
```

## 指令說明

| 指令      | 需要 sudo | 作用 |
|-----------|:--------:|------|
| `status`  | 否       | 顯示元件是否在跑（PID、CPU）以及 launchd 是否已載入 |
| `stop`    | 是       | 用 `launchctl bootout` 卸載 + 清掉殘留進程；開機後**不會**自動再啟動，直到你 `start` |
| `start`   | 是       | 用 `launchctl bootstrap` 重新載入元件 |
| `restart` | 是       | 先 `stop` 再 `start` |

## 運作原理

- **自動探索**：腳本不寫死單一 plist，而是掃描 `/Library/LaunchDaemons/tw.gov.nhi.nhiicc*.plist`
  （這台機器上有 `nhiicc` / `nhiicc2019` / `nhiicc2023` 三個），逐一讀出**每個 plist 真正的
  `Label`** 與**執行檔名**來操作。
- **stop**：對每個 plist 做 `launchctl bootout` 卸載，再 `pkill` 清掉殘留進程。
  ⚠️ 這個元件設了 **`KeepAlive`**（被殺會自動重生），所以一定要先 bootout 從 launchd 卸載，
  單純 `kill` 是沒用的。三個 plist 都要卸載，否則沒卸到的那個會把進程拉回來。
- **start**：對每個 plist 做 `launchctl bootstrap` 重新載入；失敗則退而用 `launchctl kickstart`。

### 為什麼舊版會「關不掉 / status 誤判」

- 舊版只認 `tw.gov.nhi.nhiicc.plist` 一個，但實際在管進程的是 `nhiicc2019` / `nhiicc2023`，
  所以 stop 關不乾淨。
- 這些 plist 的 `Label` 本身帶 `.plist` 後綴（例如 `tw.gov.nhi.nhiicc.plist`），舊版用
  `basename ... .plist` 砍掉後綴去查 launchd，永遠查不到 → status 永遠顯示「未載入」。

## 小提醒

- 平常不用健保卡時 `stop` 即可省 CPU；臨時要在政府網站刷卡前再 `start`。
- `status` 不需要 sudo，隨時可查。
