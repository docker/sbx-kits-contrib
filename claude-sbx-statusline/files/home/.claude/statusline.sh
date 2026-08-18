#!/usr/bin/env bash
# Claude Code status line for Docker Sandboxes (two lines).
#   line 1:  :whale: Docker Sandboxes · HOST · PWD (branch*)
#   line 2:  MODEL · ctx NN%/Wk · mem U/TG · load L · $COST
# Receives session JSON on stdin. Runs on every render, so each segment stays cheap.

input=$(cat)

# One jq pass extracts every field (one per line); renders run often, so avoid
# re-forking jq. Line-per-field read preserves empty fields (tab-splitting would
# collapse leading blanks, since tab is IFS whitespace).
{ read -r dir; read -r model; read -r pct; read -r winsz; read -r cost; } < <(printf '%s' "$input" | jq -r '
  .workspace.current_dir // .cwd // "",
  .model.display_name // "",
  .context_window.used_percentage // "",
  ((.context_window.context_window_size // 0) / 1000 | floor),
  .cost.total_cost_usd // 0')
[ -z "$dir" ] && dir=$(pwd)

# ANSI colours
RST=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
CYAN=$'\033[36m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
GREEN=$'\033[32m'; RED=$'\033[31m'; MAGENTA=$'\033[35m'
WHITE=$'\033[37m'; SEP=$'\033[90m'

# join SEGMENTS... -> non-empty segments separated by " · "
join() {
  local out="" s
  for s in "$@"; do
    [ -z "$s" ] && continue
    if [ -z "$out" ]; then out="$s"; else out="${out}${SEP} · ${RST}${s}"; fi
  done
  printf '%s' "$out"
}

# --- Git branch + dirty marker (blank when not a repo) ---
git_seg=""
if branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null); then
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    git_seg=" ${GREEN}(${branch}${RED}*${GREEN})${RST}"
  else
    git_seg=" ${GREEN}(${branch})${RST}"
  fi
fi

# --- Model ---
model_seg=""
[ -n "$model" ] && model_seg="${BOLD}${WHITE}${model}${RST}"

# --- Context, colour-coded; blank early in a session ---
ctx_seg=""
if [ -n "$pct" ] && [ "$pct" != "null" ]; then
  p=${pct%.*}
  if   [ "$p" -ge 80 ]; then c=$RED
  elif [ "$p" -ge 50 ]; then c=$YELLOW
  else c=$GREEN; fi
  ctx_seg="${c}ctx ${p}%${DIM}/${winsz}k${RST}"
fi

# --- Memory: prefer cgroup v2 limit, fall back to /proc/meminfo ---
mem_seg=""
if [ -r /sys/fs/cgroup/memory.current ] && [ -r /sys/fs/cgroup/memory.max ]; then
  cur=$(cat /sys/fs/cgroup/memory.current)
  max=$(cat /sys/fs/cgroup/memory.max)
  if [ "$max" = "max" ]; then
    max=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)
  fi
elif [ -r /proc/meminfo ]; then
  max=$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/{print $2*1024}' /proc/meminfo)
  cur=$((max - avail))
fi
if [ -n "$max" ] && [ "$max" -gt 0 ] 2>/dev/null; then
  read -r u t pctm <<<"$(awk -v c="$cur" -v m="$max" \
    'BEGIN{printf "%.1f %.1f %d", c/1073741824, m/1073741824, (c*100)/m}')"
  if   [ "$pctm" -ge 90 ]; then mc=$RED
  elif [ "$pctm" -ge 70 ]; then mc=$YELLOW
  else mc=$CYAN; fi
  mem_seg="${mc}mem ${u}/${t}G${RST}"
fi

# --- CPU 1-min load average ---
load_seg=""
if [ -r /proc/loadavg ]; then
  load=$(awk '{print $1}' /proc/loadavg)
  load_seg="${MAGENTA}load ${load}${RST}"
fi

# --- Cost ---
cost_seg="${MAGENTA}$(printf '$%.2f' "$cost")${RST}"

line1=$(join "${BOLD}${CYAN}🐳 Docker Sandboxes${RST}" "${YELLOW}$(hostname)${RST}" "${BLUE}${dir}${RST}${git_seg}")
line2=$(join "$model_seg" "$ctx_seg" "$mem_seg" "$load_seg" "$cost_seg")

printf '%s\n%s' "$line1" "$line2"
