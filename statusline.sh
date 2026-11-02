#!/bin/bash
set -f

account_file="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
IFS=$'\t' read -r account_id plan_name <<< "$(jq -r '[(.oauthAccount.accountUuid // "default")[0:8], (.oauthAccount.planDisplayName // "")] | @tsv' "$account_file" 2>/dev/null)"
account_id=${account_id:-default}
cache_file="/tmp/claude/statusline-usage-${account_id}.json"
fail_file="/tmp/claude/statusline-usage-${account_id}.fail"
lock_dir="/tmp/claude/statusline-usage-${account_id}.lock"

# statusline.sh --check: is the usage data working? Shows the plan, a live call to the
# usage endpoint, which limits the plan has, the cache state and a sample render.
if [ "$1" = "--check" ]; then
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "${HOME}/.claude/.credentials.json" 2>/dev/null)
    echo "plan:   ${plan_name:-?} · $(echo "$blob" | jq -r '.claudeAiOauth | "\(.subscriptionType // "?") (\(.rateLimitTier // "?"))"' 2>/dev/null) · account ${account_id}"
    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -z "$token" ] && token="$CLAUDE_CODE_OAUTH_TOKEN"
    if [ -z "$token" ]; then echo "token:  not found (log in to Claude Code first)"; exit 1; fi
    ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    tmp=$(mktemp)
    code=$(curl -s --max-time 8 -o "$tmp" -w "%{http_code}" -H "Accept: application/json" -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: claude-code/${ver:-2.1.0}" "https://api.anthropic.com/api/oauth/usage")
    echo "usage:  HTTP $code"
    if [ "$code" = "200" ]; then
        jq -r '"limits: " + ([.limits[]? | "\(.kind)\(if .scope.model.display_name then "(" + .scope.model.display_name + ")" else "" end) \(.percent)%"] | join(", "))' "$tmp"
        jq -r '"5-hour: " + (if .five_hour then "\(.five_hour.utilization)%" else "none on this plan" end)' "$tmp"
        mkdir -p /tmp/claude && cp "$tmp" "$cache_file" && rm -f "$fail_file"
    fi
    rm -f "$tmp"
    for f in "$cache_file" "$fail_file"; do
        [ -f "$f" ] && echo "file:   $f ($(( $(date +%s) - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f") ))s old)"
    done
    echo "render:"
    printf '{"model":{"display_name":"Opus 5.5"},"version":"%s","context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":99000}}}' "${ver:-2.1.0}" | bash "$0"
    echo
    [ "$code" = "200" ] && exit 0 || exit 1
fi

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}|${reset} "

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

format_reset_time() {
    local iso_str="$1"
    local style="$2"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    case "$style" in
        time)
            date -j -r "$epoch" +"%l:%M %p" 2>/dev/null | sed 's/^ //' || \
            date -d "@$epoch" +"%l:%M %p" 2>/dev/null | sed 's/^ //'
            ;;
        datetime)
            date -j -r "$epoch" +"%b %-d, %l:%M %p" 2>/dev/null | sed 's/  / /g; s/^ //' || \
            date -d "@$epoch" +"%b %-d, %l:%M %p" 2>/dev/null | sed 's/  / /g; s/^ //'
            ;;
    esac
}

build_bar() {
    local pct=$1
    local width=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local bar_filled='\033[38;2;221;129;97m'
    local bar_empty='\033[38;2;80;60;50m'

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="▆"; done
    for ((i=0; i<empty; i++)); do empty_str+="▆"; done

    printf "${bar_filled}${filled_str}${bar_empty}${empty_str}${reset}"
}

format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

IFS=$'\t' read -r model_name size input_tokens cache_create cache_read cc_version <<< "$(echo "$input" | jq -r '[
    .model.display_name // "Claude",
    .context_window.context_window_size // 200000,
    .context_window.current_usage.input_tokens // 0,
    .context_window.current_usage.cache_creation_input_tokens // 0,
    .context_window.current_usage.cache_read_input_tokens // 0,
    .version // "2.1.0"
] | @tsv')"
[ "$size" -eq 0 ] 2>/dev/null && size=200000
current=$(( input_tokens + cache_create + cache_read ))

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

context_bar=$(build_bar "$pct_used" 10)
context_pct_fmt=$(printf "%3d" "$pct_used")

plan_part=""
[ -n "$plan_name" ] && plan_part="${dim}${plan_name}${reset}${sep}"
line1="${white}${model_name}${reset}${sep}${plan_part}${context_bar} ${white}${context_pct_fmt}%${reset}${sep}${white}${used_tokens}/${total_tokens}${reset}"

get_oauth_token() {
    local token=""

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    local creds_file="${HOME}/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    # Last: a `claude setup-token` token (CLAUDE_CODE_OAUTH_TOKEN) has no user:profile scope, so the usage endpoint answers it 403.
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

cache_max_age=120
mkdir -p /tmp/claude

file_age() {
    local m
    m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
    echo $(( $(date +%s) - m ))
}

# The usage endpoint answers 429 to unknown user agents and to bursts, so one session
# refreshes at a time, at most every 2 minutes, and waits 5 minutes after a failure.
fetch_usage() {
    local token code tmp="/tmp/claude/statusline-usage.$$"
    token=$(get_oauth_token)
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "no-token" > "$fail_file"
        return 1
    fi
    code=$(curl -s --max-time 5 -o "$tmp" -w "%{http_code}" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/${cc_version:-2.1.0}" \
        "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ "$code" = "200" ] && jq -e '.limits // .seven_day' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$cache_file"
        rm -f "$fail_file"
        return 0
    fi
    rm -f "$tmp"
    echo "${code:-000}" > "$fail_file"
    return 1
}

[ -d "$lock_dir" ] && [ "$(file_age "$lock_dir" || echo 0)" -gt 30 ] && rmdir "$lock_dir" 2>/dev/null
cache_age=$(file_age "$cache_file" || echo 999999)
fail_age=$(file_age "$fail_file" || echo 999999)
if [ "$cache_age" -ge "$cache_max_age" ] && [ "$fail_age" -ge 300 ] && mkdir "$lock_dir" 2>/dev/null; then
    fetch_usage
    rmdir "$lock_dir" 2>/dev/null
    cache_age=$(file_age "$cache_file" || echo 999999)
fi
usage_data=$(cat "$cache_file" 2>/dev/null)

rate_lines=""

if [ -n "$usage_data" ]; then
    # Plans list their limits in .limits: a 5-hour session limit ("Current", only on plans that
    # have one; the $200 Ultra plan doesn't), weekly, and per-model weekly. Older responses only have five_hour / seven_day.
    rows=$(echo "$usage_data" | jq -r '
        (if (.limits | type) == "array" and (.limits | length) > 0 then
            [.limits[]
             | select(.kind == "session" or .kind == "weekly_all"
                      or (.kind == "weekly_scoped" and ((.percent // 0) > 0 or .is_active == true)))
             | [ (if .kind == "session" then "Current"
                  elif .kind == "weekly_all" then "Weekly"
                  else (.scope.model.display_name // .scope.surface // "Scoped") end),
                 (.percent // 0 | round), (.resets_at // "null"),
                 (if .kind == "session" then "time" else "datetime" end) ]]
         else
            [ (if .five_hour then ["Current", (.five_hour.utilization // 0 | round), (.five_hour.resets_at // "null"), "time"] else empty end),
              (if .seven_day then ["Weekly", (.seven_day.utilization // 0 | round), (.seven_day.resets_at // "null"), "datetime"] else empty end) ]
         end)[] | @tsv')
    # Monthly dollar allowance that comes with the plan.
    credit=$(echo "$usage_data" | jq -r '[.[] | objects | select(.limit_dollars != null and .used_dollars != null)][0]
        | select(. != null) | [(.utilization // 0 | round), (.used_dollars | tostring), (.limit_dollars | tostring), (.resets_at // "null")] | @tsv')

    while IFS=$'\t' read -r label pct reset_iso style; do
        [ -z "$label" ] && continue
        [ -n "$rate_lines" ] && rate_lines+="\n"
        rate_lines+="${white}$(printf '%-7s' "$label")${reset}${sep}$(build_bar "$pct" 10) ${white}$(printf '%3d' "$pct")%${reset}${sep}${white}$(format_reset_time "$reset_iso" "$style")${reset}"
    done <<< "$rows"

    if [ -n "$credit" ]; then
        IFS=$'\t' read -r c_pct c_used c_limit c_reset <<< "$credit"
        c_used_fmt=$(awk "BEGIN {printf \"%.2f\", $c_used}")
        [ -n "$rate_lines" ] && rate_lines+="\n"
        rate_lines+="${white}Credit ${reset}${sep}$(build_bar "$c_pct" 10) ${white}$(printf '%3d' "$c_pct")%${reset}${sep}${white}\$${c_used_fmt}/\$${c_limit} · $(format_reset_time "$c_reset" "datetime")${reset}"
    fi

    if [ "$cache_age" -gt 600 ]; then
        rate_lines+="\n${dim}usage from $(date -r $(( $(date +%s) - cache_age )) +"%b %-d %H:%M") (refresh failing: $(cat "$fail_file" 2>/dev/null || echo "?"))${reset}"
    fi
fi

printf "%b" "$line1"
[ -n "$rate_lines" ] && printf "\n\n%b" "$rate_lines"

exit 0
