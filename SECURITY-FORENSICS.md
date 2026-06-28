# 供應鏈攻擊鑑識工具 (Supply-Chain Forensics)

針對 npm / pip 等套件供應鏈攻擊的**唯讀**鑑識與防護工具組。
適用情境:引用的套件被植入惡意碼,於**安裝期竊取機敏資料**(env / .env / 私鑰 / SSH key / token / 錢包 / 雲端憑證)或**執行期挖礦**,且攻擊常在 `/tmp/<亂數>` 落地並自刪痕跡。

| 腳本 | 平台 | 用途 |
|---|---|---|
| `linux-supply-chain-forensics.sh` | Linux | 受害機鑑識(9 大類檢查) |
| `macos-supply-chain-forensics.sh` | macOS | 同上,改用 macOS 原生工具 + 簽章驗證 |
| `nhiicc-toggle.sh` | macOS | 啟停健保卡元件(高 CPU 元件,非惡意,附帶工具) |

> ⚠️ **核心觀念:腳本「沒發現」≠「沒中標」。** 此類攻擊會自刪證據。只要曾在該機開發過受影響專案,**一律假設金鑰/token 已外洩,全部輪換**,並查雲端側日誌(AWS CloudTrail / GitHub Security log)——那才是攻擊者刪不掉的證據。

---

## 1. 鑑識腳本用法

兩支腳本皆為**唯讀**:不刪檔、不殺進程、不改設定。只蒐證並標記。

```bash
# Linux 受害機
chmod +x linux-supply-chain-forensics.sh
sudo ./linux-supply-chain-forensics.sh        # 建議 sudo,覆蓋最完整

# macOS
chmod +x macos-supply-chain-forensics.sh
sudo ./macos-supply-chain-forensics.sh
```

報告會同時輸出到畫面與家目錄:`~/forensics-report[-mac]-<時間>.txt`

### 輸出判讀

| 標記 | 顏色 | 意義 |
|---|---|---|
| `[!! 可疑]` | 紅 | 命中指標,**需逐項追查** |
| `[注意]` | 黃 | 需人工研判(可能是正常 App 的副作用) |
| `[OK]` | 綠 | 該項通過 |
| 結尾 | — | 顯示總命中數 |

---

## 2. 各檢查項目(對應攻擊手法)

### Linux 版(9 段)

| # | 檢查 | 對應攻擊 |
|---|---|---|
| 1 | 挖礦特徵進程 + **從 /tmp 或「已刪除映像」執行的進程**(讀 `/proc/<pid>/exe`) | 執行期挖礦 + 自刪手法 |
| 2 | `/tmp` `/var/tmp` `/dev/shm` 可執行檔、亂數/PID 命名項目 | `/tmp/xxxx` 落地 |
| 3 | 持久化:cron(系統+使用者+cron.d)、systemd unit/timer、rc.local、shell rc 注入、`/etc/ld.so.preload` | 常駐 / rootkit |
| 4 | **SSH 橫向移動**:authorized_keys 逐行列出、**無 passphrase 私鑰**、known_hosts 範圍 | 用 SSH key 跳 AWS |
| 5 | 對外連線(`ss`/`netstat`)+ 監聽埠 | 資料外洩 / 礦池 |
| 6 | npm:`_logs`、已知遭攻陷套件 IOC(**版本感知**)、含 install 腳本又讀 AWS/SSH/token 的套件 | 安裝期竊密源頭 |
| 7 | Shell 歷史 `curl\|bash` / base64 混淆 | 下載執行痕跡 |
| 8 | 套件管理器 log + auth.log 登入紀錄 | 較難被清的旁證 |
| 9 | 近 14 天新建的可執行檔 | 殘留物 |

### macOS 版(對稱,改用原生工具)

- `/proc` → `lsof`(查 /tmp 執行 + 對外連線)
- `iptables`/`systemd` → `launchctl` / LaunchAgents / LaunchDaemons
- **`codesign -dv` 驗簽章**(macOS 獨有強項:快速分辨「官方簽章」vs「來路不明」)
- `auth.log` → `log show`(統一日誌)
- npm IOC / shell 歷史邏輯與 Linux 版共用

#### npm IOC 為「版本感知」(兩版共用)
比對的是**實際安裝版本 vs 已知惡意版本**,不是只比對套件名稱。
像 `coa`、`ua-parser-js`、`event-stream`、`eslint-scope`、`rc` 這些「曾經某個版本中標、但早已修好」的熱門套件,
只有裝到**確切的惡意版本**才告警,乾淨版本不會誤報。清單為代表性(非窮舉),新型變種未必涵蓋。

#### macOS 版已內建的誤報過濾
- **`/tmp` 映射**:對涉及的進程驗簽章,已知開發者(如 Kensington 驅動用 boost 共享記憶體)降為「注意」而非紅色
- **plist**:把 log 寫到 `/tmp` 的合法 App(Adobe / Logitech 的 `StandardOutPath`)不誤判為下載指令
- **shell rc**:放行 `eval "$(brew shellenv)"` 等常見合法寫法,只抓真正的 `curl|bash` / 對 curl/base64 結果做 eval

---

## 3. 中標後的處置順序

1. **輪換所有憑證**:SSH key、雲端(改短期憑證,撤銷 static key)、GitHub PAT/OAuth、各 API token、錢包(助記詞洩漏的錢包等於廢了,資產轉移)
2. **查雲端日誌**:CloudTrail 異常 API / 新 IAM / 新 EC2;GitHub Security log 異常登入
3. **重建環境**:用隔離環境(Dev Container / VM)重建,別在宿主機直接跑陌生套件
4. SSH key 加 **15 碼以上 passphrase**,更強的用 **FIDO2 硬體金鑰**(`ssh-keygen -t ed25519-sk`,私鑰無法被複製外洩)

> 完整的隔離開發環境範本(Dev Container + 出向白名單 + 機密不落地)見:
> `~/projects/secure-devcontainer-template/`

---

## 4. 預防(降低再次中標機率)

- **禁用 npm 安裝腳本**:`npm config set ignore-scripts true`(擋掉絕大多數安裝期竊密;需 build 的套件用 `npm rebuild <pkg>` 針對性放行)
- **冷卻期**:不要套件一發布就升級(惡意版本通常數小時~數天內被抓掉);用 Socket.dev / OSV-Scanner 預掃
- **出向白名單**:預設拒絕所有 outbound,只放行 registry / git / 必要 API——資料就算被偷也送不出去、礦池連不上(鎖 inbound IP 對這類主動外連無效)
- **機密不落地**:別把長期金鑰塞進 `.env` / shell rc;用 1Password CLI / vault 動態注入,雲端用 `aws sso` 短期憑證

---

## 5. harden-package-managers.sh(關閉安裝期腳本)

一鍵關閉各套件管理器的 `preinstall`/`postinstall` 腳本——擋掉約 9 成「安裝期竊密」。冪等,可重複執行。

```bash
./harden-package-managers.sh status   # 只查狀態
./harden-package-managers.sh          # 套用(npm 設 ignore-scripts=true,寫入 ~/.npmrc)
./harden-package-managers.sh revert    # 還原
```

涵蓋:
- **npm**:`ignore-scripts=true`(一次設定,跨所有專案永久生效)
- **pnpm**:10+ 預設已封鎖;舊版透過 `~/.npmrc` 涵蓋
- **yarn**:Berry 設 `enableScripts: false`;Classic 1.x 無全域設定,給出 flag / 包裝 / 換工具建議
- **bun**:預設即封鎖未信任套件,僅回報狀態

> 只影響未來安裝,不保護已裝好的 `node_modules`。合法 build 被擋時用 `npm rebuild <pkg>` 針對性放行。

---

## 6. ssh-add-passphrases.sh(替既有私鑰補 passphrase)

互動式掃描 `~/.ssh` 下「沒加 passphrase」的私鑰,逐把呼叫 `ssh-keygen -p` 補上。
加 passphrase **不改變公鑰、不影響伺服器端**,只加密本機私鑰檔。

```bash
./ssh-add-passphrases.sh --dry-run   # 只列出哪些沒加密
./ssh-add-passphrases.sh             # 互動逐把加(請在自己的終端機跑,需 TTY 輸入密碼)
```

判斷邏輯:舊格式看標頭(`ENCRYPTED`/`DEK-Info`),新 OpenSSH 格式靠「空密碼能否解開」。
相容 macOS 內建 bash 3.2。

> ⚠️ **對已外洩的 key 加 passphrase 無效** —— 攻擊者已有未加密副本。
> 曾在受害機上的正式機 / AWS / bastion key 應「**重新產生** + 換掉伺服器公鑰 + 撤銷舊的」,
> 而非只加 passphrase。本機自用且確定沒外洩的 key 才適合單純補 passphrase。

加完建議存進 keychain 免每次輸入:
```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
# ~/.ssh/config:  Host *
#                     UseKeychain yes
#                     AddKeysToAgent yes
```

---

## 7. 附:nhiicc-toggle.sh(健保卡元件啟停)

健保卡網路服務元件 (mNHIICC) 由健保署官方簽章 (Team ID `NRMY799KE6`),**是合法程式**,但常駐時很吃 CPU 且設了 KeepAlive(被殺會自動重生)。沒在用讀卡機時可關掉:

```bash
~/projects/scripts/nhiicc-toggle.sh status     # 看狀態(不需 sudo)
sudo ~/projects/scripts/nhiicc-toggle.sh stop  # 停止(launchctl bootout,開機不再自動啟動)
sudo ~/projects/scripts/nhiicc-toggle.sh start # 要用健保卡時再開
sudo ~/projects/scripts/nhiicc-toggle.sh restart
```
