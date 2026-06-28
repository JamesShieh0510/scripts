#!/usr/bin/env bash
#
# macos-supply-chain-forensics.sh
# 唯讀鑑識腳本 (macOS 版) — npm/pip 供應鏈攻擊:安裝期竊密 + 執行期挖礦
#
# 與 Linux 版對稱,但改用 macOS 原生工具:
#   lsof (查 /tmp 執行 + 對外連線)、launchctl/Launch* (持久化)、
#   codesign (★驗簽章,Mac 獨有強項)、log show (系統日誌)。
#
# 唯讀:不刪檔、不殺進程、不改設定。
# 用法:
#   chmod +x macos-supply-chain-forensics.sh
#   sudo ./macos-supply-chain-forensics.sh    # 建議 sudo,覆蓋最完整
#
set -uo pipefail

REPORT="${HOME}/forensics-report-mac-$(date +%Y%m%d-%H%M%S).txt"
FINDINGS=0

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "$*" | tee -a "$REPORT"; }
hdr()  { log "\n${CYN}===== $* =====${NC}"; }
ok()   { log "${GRN}  [OK] $*${NC}"; }
warn() { log "${YEL}  [注意] $*${NC}"; }
hit()  { log "${RED}  [!! 可疑] $*${NC}"; FINDINGS=$((FINDINGS+1)); }
note() { log "       $*"; }

{
echo "macOS 供應鏈攻擊鑑識報告"
echo "時間: $(date)"
echo "主機: $(hostname 2>/dev/null)"
echo "系統: $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
echo "執行身分: $(id -un) (uid=$(id -u))"
[ "$(id -u)" -ne 0 ] && echo "提示: 非 root,部分項目覆蓋不完整,建議 sudo"
echo "報告檔: $REPORT"
} | tee "$REPORT"

# =====================================================================
hdr "1. 執行期挖礦偵測 + 從暫存區執行的進程"
# =====================================================================
log "  -- CPU 前 10 名進程 --"
ps -Ao pid,ppid,user,%cpu,%mem,comm -r 2>/dev/null | head -11 | tee -a "$REPORT"

MINER_PAT='xmrig|xmr-stak|minerd|cpuminer|ccminer|ethminer|nbminer|t-rex|kdevtmpfsi|kinsing|monero|stratum|nicehash|randomx'
log "  -- 比對挖礦特徵字 --"
if ps -Ao pid,user,args 2>/dev/null | grep -iE "$MINER_PAT" | grep -v grep | grep -qv forensics; then
    ps -Ao pid,user,args 2>/dev/null | grep -iE "$MINER_PAT" | grep -v grep | grep -v forensics | while read -r l; do hit "挖礦特徵: $l"; done
else
    ok "未發現已知挖礦進程"
fi

log "  -- 執行映像/映射位於 /tmp /var/tmp /private/tmp 的進程 (lsof + 驗簽章) --"
tmp_exec=$(lsof -nP 2>/dev/null | awk '$4=="txt" && ($NF ~ /^\/private\/tmp\// || $NF ~ /^\/tmp\// || $NF ~ /^\/var\/tmp\//) {print $2"|"$NF}' | sort -u)
if [ -n "$tmp_exec" ]; then
    # 對每個涉及的 PID 驗簽章:已知開發者簽章 → 降級為注意(多為 boost 共享記憶體等正常用法)
    echo "$tmp_exec" | awk -F'|' '{print $1}' | sort -u | while read -r pid; do
        bin=$(ps -o comm= -p "$pid" 2>/dev/null)
        auth=$(codesign -dv --verbose=2 "$bin" 2>&1 | grep -E '^Authority=' | head -1)
        paths=$(echo "$tmp_exec" | awk -F'|' -v p="$pid" '$1==p{print $2}' | tr '\n' ' ')
        if echo "$auth" | grep -qiE 'Apple|Developer ID'; then
            warn "PID $pid ($bin) 映射 /tmp 檔但簽章正常 [$auth] — 多為共享記憶體,非惡意: $paths"
        else
            hit "PID $pid ($bin) 從暫存區執行且簽章不明 [${auth:-無簽章}]: $paths"
        fi
    done
else
    ok "無從暫存區執行的進程"
fi

# =====================================================================
hdr "2. 暫存區落地檔案 (/tmp /var/tmp 可執行 / 亂數命名)"
# =====================================================================
for d in /tmp /private/tmp /var/tmp; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 3 -type f -perm -u+x 2>/dev/null | grep -v forensics | head -30 | while read -r f; do
        hit "暫存區可執行檔: $f  ($(stat -f '%Sm %Su %z bytes' "$f" 2>/dev/null))"
    done
    find "$d" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | grep -E '/[a-f0-9]{8,}$|/[0-9]{4,}$' | head -20 | while read -r f; do
        warn "亂數/數字命名目錄(需研判): $f"
    done
done
ok "(以上若無紅色項目,代表暫存區無可執行落地檔)"

# =====================================================================
hdr "3. 持久化機制 (launchd / cron / shell rc)"
# =====================================================================
log "  -- 非 Apple 的 LaunchDaemons/LaunchAgents 中指向暫存區或含下載指令者 --"
hit_persist=0
for dir in /Library/LaunchDaemons /Library/LaunchAgents ~/Library/LaunchAgents; do
    [ -d "$dir" ] || continue
    for p in "$dir"/*.plist; do
        [ -f "$p" ] || continue
        # 真正高危:下載執行 / 編碼混淆 / dev.shm / onion
        if grep -aqE 'curl|wget|base64 -[dD]|/dev/shm|\.onion' "$p" 2>/dev/null; then
            hit "可疑 plist(下載/混淆指令): $p"; grep -anE 'curl|wget|base64|/dev/shm|\.onion' "$p" 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"; hit_persist=1
        fi
        # /tmp 路徑:排除把 log 寫到 /tmp 的合法 App(StandardOut/ErrPath、.log/.err/.out),其餘才提醒人工研判
        tmpref=$(grep -anE '/tmp/|/var/tmp/' "$p" 2>/dev/null | grep -ivE 'StandardOutPath|StandardErrorPath|\.log|\.err|\.out')
        if [ -n "$tmpref" ]; then
            warn "plist 含非 log 的 /tmp 路徑(研判): $p"; echo "$tmpref" | sed 's/^/        /' | tee -a "$REPORT"
        fi
    done
done
[ "$hit_persist" -eq 0 ] && ok "LaunchDaemons/Agents 無指向暫存區或下載指令者"

log "  -- 近 30 天新建的 Launch* plist (供人工比對是否你安裝的) --"
find /Library/LaunchDaemons /Library/LaunchAgents ~/Library/LaunchAgents -name '*.plist' -mtime -30 2>/dev/null | while read -r p; do
    note "$p  ($(stat -f '%Sm' "$p" 2>/dev/null))"
done

log "  -- crontab --"
crontab -l 2>/dev/null | grep -vE '^\s*#' | sed 's/^/        /' | tee -a "$REPORT" || note "(無 crontab)"

log "  -- shell 啟動檔注入 (curl|bash / base64 / eval) --"
for rc in ~/.zshrc ~/.bashrc ~/.bash_profile ~/.profile ~/.zprofile /etc/zshrc /etc/profile; do
    [ -f "$rc" ] || continue
    # 收窄:只抓「下載執行」與「對 curl/base64 結果做 eval」這種真正危險的;
    # 放行 eval "$(brew shellenv)" 等常見合法寫法
    m=$(grep -nE 'curl.*\|.*sh|wget.*\|.*sh|/tmp/[a-z0-9]{4,}|base64\s+-[dD]|eval[^)]*\$\((curl|wget|base64)' "$rc" 2>/dev/null)
    [ -n "$m" ] && { hit "$rc 含可疑注入:"; echo "$m" | sed 's/^/        /' | tee -a "$REPORT"; }
done
ok "(若上面無紅色項目,shell 啟動檔乾淨)"

# =====================================================================
hdr "4. ★簽章驗證:非 Apple 且高 CPU / root 的可疑進程"
# =====================================================================
log "  -- 對 CPU 前幾名的非系統進程驗簽章 (來路不明 = 可疑) --"
ps -Ao pid,%cpu,user,comm -r 2>/dev/null | awk 'NR>1 && NR<=12 {print $1}' | while read -r pid; do
    exe=$(ps -o comm= -p "$pid" 2>/dev/null)
    [ -z "$exe" ] && continue
    case "$exe" in /System/*|/usr/libexec/*|/usr/sbin/*|/usr/bin/*) continue;; esac
    auth=$(codesign -dv --verbose=2 "$exe" 2>&1 | grep -E '^Authority=' | head -1)
    if [ -z "$auth" ]; then
        sig=$(codesign -v "$exe" 2>&1 | head -1)
        if echo "$sig" | grep -qiE 'not signed|invalid|modified'; then
            hit "未簽章/簽章無效: $exe  ($sig)"
        else
            note "$exe : (無 Authority 行,但簽章存在)"
        fi
    else
        note "$exe : $auth"
    fi
done
ok "(Authority 顯示 Apple / 已知開發者 = 正常;'未簽章/簽章無效' 才需追查)"

# =====================================================================
hdr "5. 對外網路連線 (外洩 / 礦池)"
# =====================================================================
log "  -- 已建立的對外連線 (排除本機/內網) --"
lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -ivE '127\.0\.0\.1|\[::1\]|->(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | awk 'NR==1 || $0 ~ /->/ {print $1, $2, $3, $9}' | head -40 | tee -a "$REPORT"
log "  -- 監聽中的埠 --"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || NR<=25 {print $1, $2, $3, $9}' | tee -a "$REPORT"

# =====================================================================
hdr "6. npm / Node 供應鏈跡證"
# =====================================================================
log "  -- ~/.npm/_logs 近期紀錄 --"
ls -lt ~/.npm/_logs 2>/dev/null | head -6 | sed 's/^/        /' | tee -a "$REPORT" || note "(無 npm logs)"

log "  -- 已知遭攻陷 npm 套件比對 (代表性,非窮舉) --"
IOC_PKGS="node-ipc @ctrl/tinycolor rand-user-agent @ctrl/deluge coa rc ua-parser-js event-stream flatmap-stream getcookies eslint-scope"
ioc_found=0
for p in $IOC_PKGS; do
    find "$HOME" -maxdepth 8 -type d -path "*/node_modules/$p" 2>/dev/null | head -2 | while read -r d; do
        echo "HIT|$p|$d"
    done
done | while IFS='|' read -r _ p d; do hit "已知遭攻陷套件 $p: $d"; done
ok "(若無紅色項目,代表未命中已知 IOC;新型變種未必在清單內)"

# =====================================================================
hdr "7. Shell 歷史:下載執行 / 編碼混淆"
# =====================================================================
for hist in ~/.zsh_history ~/.bash_history ~/.local/share/fish/fish_history; do
    [ -f "$hist" ] || continue
    m=$(grep -aiE 'curl.*\|.*(ba)?sh|wget.*\|.*(ba)?sh|/tmp/[a-z0-9]{4,}|base64\s+-[dD]|eval\s+.*\$\(|chmod\s+\+x\s+/tmp' "$hist" 2>/dev/null)
    [ -n "$m" ] && { hit "$hist 含下載執行/混淆:"; echo "$m" | tail -15 | sed 's/^/        /' | tee -a "$REPORT"; }
done
ok "(若無紅色項目,歷史無明顯下載執行痕跡;但可能被清過)"

# =====================================================================
hdr "8. SSH 設定 + 近期系統事件"
# =====================================================================
if [ -f ~/.ssh/authorized_keys ]; then
    log "  -- ~/.ssh/authorized_keys (逐行確認都是你認得的) --"
    grep -vE '^\s*#|^\s*$' ~/.ssh/authorized_keys 2>/dev/null | sed 's/^/        /' | tee -a "$REPORT"
    warn "不認得的 key 立即移除"
fi
for key in ~/.ssh/id_* ~/.ssh/*.pem; do
    [ -f "$key" ] || continue
    case "$key" in *.pub) continue;; esac
    if head -3 "$key" 2>/dev/null | grep -q "PRIVATE KEY" && ! grep -q "ENCRYPTED\|DEK-Info\|bcrypt" "$key" 2>/dev/null; then
        hit "未加密(無 passphrase)私鑰: $key  ← 外洩即可直接登入,建議重設並加長 passphrase"
    fi
done
log "  -- 近 7 天的安裝/載入相關系統事件 (log show) --"
log show --last 7d --predicate 'eventMessage CONTAINS "LaunchDaemon" OR eventMessage CONTAINS[c] "tmp/"' --style compact 2>/dev/null | grep -iE 'curl|/tmp/|base64|wget' | head -15 | sed 's/^/        /' | tee -a "$REPORT" || true

# =====================================================================
hdr "結論"
# =====================================================================
if [ "$FINDINGS" -eq 0 ]; then
    log "${GRN}本次掃描未命中明確的 [!! 可疑] 指標。${NC}"
    log "${YEL}但這不代表沒中標 — 此類攻擊會自刪證據。仍請:${NC}"
else
    log "${RED}共命中 $FINDINGS 個可疑指標,請逐項複查上方紅色項目。${NC}"
fi
log "  1. 若曾在此機開發過受影響專案,假設金鑰/token 已外洩,全部輪換"
log "  2. 查雲端側日誌 (AWS CloudTrail / GitHub Security log) — 攻擊者刪不掉"
log "  3. 用隔離環境 (Dev Container / VM) 重建開發環境"
log "\n完整報告: ${CYN}$REPORT${NC}"
