#!/bin/bash
# nhiicc-toggle.sh — 啟動 / 停止 健保卡網路服務元件 (mNHIICC)
# 這個元件由健保署官方簽章 (Team ID NRMY799KE6)，是合法程式，
# 但常駐時很吃 CPU，且設了 KeepAlive(被殺會自動重生)。
# 沒在用健保卡讀卡機時可以關掉，要用時再開。
#
# 不寫死單一 plist：自動掃描 /Library/LaunchDaemons 下所有
# tw.gov.nhi.nhiicc*.plist(可能有 nhiicc / nhiicc2019 / nhiicc2023)，
# 並讀出每個 plist「真正的 Label」與「執行檔名」來操作，避免關不乾淨或誤判。
#
# 用法:
#   ./nhiicc-toggle.sh status    查看目前狀態
#   ./nhiicc-toggle.sh stop      停止 (需要 sudo)
#   ./nhiicc-toggle.sh start     啟動 (需要 sudo)
#   ./nhiicc-toggle.sh restart   重啟 (需要 sudo)

set -euo pipefail

PLIST_GLOB="/Library/LaunchDaemons/tw.gov.nhi.nhiicc*.plist"
DOMAIN="system"
# 額外保險：健保署元件常見的伴隨進程名(掃 plist 找不到時的後援)
EXTRA_PROCS=("macHC")

color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
green() { color "0;32" "$1"; }
red()   { color "0;31" "$1"; }
yellow(){ color "0;33" "$1"; }
dim()   { color "0;90" "$1"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        red "此操作需要 root 權限，請用 sudo 執行："
        echo "    sudo $0 ${1:-}"
        exit 1
    fi
}

# 掃出所有相關 plist(用 nullglob，沒檔案時回空陣列)
discover_plists() {
    local f
    PLISTS=()
    shopt -s nullglob
    for f in $PLIST_GLOB; do PLISTS+=("$f"); done
    shopt -u nullglob
}

# 讀出 plist 的真正 Label(健保署的 Label 可能帶 .plist 後綴，所以不能用 basename 砍)
label_of() {
    local plist="$1" lbl=""
    lbl=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null) || true
    if [ -z "$lbl" ]; then
        lbl=$(defaults read "${plist%.plist}" Label 2>/dev/null) || true
    fi
    # 真的讀不到才退回用檔名(去掉 .plist)
    [ -n "$lbl" ] && printf '%s' "$lbl" || basename "$plist" .plist
}

# 讀出 plist 指向的執行檔名(用來 pkill)；同時支援 Program 與 ProgramArguments[0]
proc_of() {
    local plist="$1" prog=""
    prog=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null) || true
    if [ -z "$prog" ]; then
        prog=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null) || true
    fi
    [ -n "$prog" ] && basename "$prog" || true
}

# 蒐集所有要 kill 的進程名(去重)
collect_procs() {
    local p name
    PROCS=()
    for p in "${PLISTS[@]}"; do
        name=$(proc_of "$p")
        [ -n "$name" ] && PROCS+=("$name")
    done
    PROCS+=("${EXTRA_PROCS[@]}")
    # 去重
    PROCS=($(printf '%s\n' "${PROCS[@]}" | awk 'NF && !seen[$0]++'))
}

status() {
    discover_plists
    echo "===== 健保卡元件 (nhiicc) 狀態 ====="

    if [ "${#PLISTS[@]}" -eq 0 ]; then
        red "✗ 找不到任何 tw.gov.nhi.nhiicc*.plist，元件可能未安裝"
        return
    fi

    collect_procs

    # --- 進程狀態 ---
    local any=0 name pids cpu
    for name in "${PROCS[@]}"; do
        if pgrep -x "$name" >/dev/null 2>&1; then
            pids=$(pgrep -x "$name" | tr '\n' ' ')
            cpu=$(ps -Ao %cpu,comm | awk '$2=="'"$name"'"{s+=$1} END{printf "%.1f", s+0}')
            green "● ${name} 執行中 (PID: ${pids%% }, CPU: ${cpu}%)"
            any=1
        fi
    done
    [ "$any" -eq 0 ] && yellow "○ 未執行"

    # --- launchd 載入狀態(逐個 plist 用真正的 Label 判斷)---
    echo "  --- launchd ---"
    local plist lbl
    for plist in "${PLISTS[@]}"; do
        lbl=$(label_of "$plist")
        if launchctl print "${DOMAIN}/${lbl}" >/dev/null 2>&1; then
            echo "  已載入   : ${lbl}  (開機會自動啟動)"
        else
            echo "  未載入   : ${lbl}"
        fi
    done
    [ "$(id -u)" -ne 0 ] && dim "  (註：非 root 時 launchd 載入狀態可能查不到，sudo 執行最準)"
}

stop() {
    need_root stop
    discover_plists
    collect_procs

    if [ "${#PLISTS[@]}" -eq 0 ]; then
        red "✗ 找不到任何 plist，無法停止"; exit 1
    fi

    echo "停止健保卡元件…"
    # 1) 把每個 plist 從 launchd 卸載(開機不再自動啟動，直到再次 start)
    local plist lbl
    for plist in "${PLISTS[@]}"; do
        lbl=$(label_of "$plist")
        echo "  bootout: ${lbl}"
        launchctl bootout "$DOMAIN" "$plist" 2>/dev/null || \
            launchctl bootout "${DOMAIN}/${lbl}" 2>/dev/null || true
    done

    # 2) 清掉殘留進程(KeepAlive 卸載後就不會再重生)
    local name
    for name in "${PROCS[@]}"; do
        pkill -x "$name" 2>/dev/null || true
    done
    sleep 1
    for name in "${PROCS[@]}"; do
        if pgrep -x "$name" >/dev/null 2>&1; then
            red "  ✗ ${name} 仍殘留，強制結束…"
            pkill -9 -x "$name" 2>/dev/null || true
        fi
    done

    green "✓ 已停止"
}

start() {
    need_root start
    discover_plists

    if [ "${#PLISTS[@]}" -eq 0 ]; then
        red "✗ 找不到任何 plist，元件可能未安裝"; exit 1
    fi

    echo "啟動健保卡元件…"
    local plist lbl
    for plist in "${PLISTS[@]}"; do
        lbl=$(label_of "$plist")
        echo "  bootstrap: ${lbl}"
        launchctl bootstrap "$DOMAIN" "$plist" 2>/dev/null || \
            launchctl kickstart -k "${DOMAIN}/${lbl}" 2>/dev/null || true
    done

    green "✓ 已啟動"
}

case "${1:-status}" in
    status)  status ;;
    stop)    stop; echo; status ;;
    start)   start; echo; status ;;
    restart) stop; sleep 1; start; echo; status ;;
    *)
        echo "用法: $0 {status|start|stop|restart}"
        exit 1
        ;;
esac
