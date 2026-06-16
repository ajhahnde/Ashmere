# Theria dev shell helpers — launch the game client from source for a local
# playtest, straight from the terminal (no editor or extra tooling needed).
# Source from ~/.zshrc:
#   [[ -f /Users/antonhahn/theria/env.zsh ]] && source /Users/antonhahn/theria/env.zsh
#
# Public interface — one verb dispatcher, `run`:
#   run                            launch the client to its connect menu (Practice/Host/Join)
#   run <hero> [flags]             local practice as <hero> (lion cheetah hyena snake spider chameleon)
#   run --host | --join <a> | …    pass flags straight to the client (you pick the mode)
#   run menu                       explicit connect menu (same as no args)
#   run import                     refresh Godot's import / global-class cache only
#   run stop                       stop the running client
#   run log [N]                    show the last N lines of the launch log (default 40)
#   run help
#
# It launches windowed FROM SOURCE (never builds a .pck, never touches an
# installed app, never commits). The client's boot scene now
# ignores the installed update payload on a source/editor run, so this always plays
# the working tree — not the last-downloaded shipped build.
#
# env overrides:
#   THERIA_GODOT=<path>   the godot binary (else `command -v godot`, then /opt/homebrew/bin/godot)
#   THERIA_NO_IMPORT=1    skip the pre-launch import refresh (faster relaunch when no
#                         new `class_name` script was added since the last run)

# Resolve the directory of this file once at source time — it IS the project root
# (env.zsh lives next to project.godot). Inside a function ${0:A:h} would name the
# function, so capture %x while it still points at the file being sourced.
typeset -g _THERIA_DIR="${${(%):-%x}:A:h}"

typeset -g _THERIA_RED=$'\033[0;31m'
typeset -g _THERIA_GREEN=$'\033[0;32m'
typeset -g _THERIA_YELLOW=$'\033[1;33m'
typeset -g _THERIA_NC=$'\033[0m'

# The hero pool, for messages + tab-completion. Mirrors AbilityData.TRIBE — Solane
# (lion cheetah hyena) and Verdani (snake spider chameleon).
typeset -ga _THERIA_HEROES=(lion cheetah hyena snake spider chameleon)

# Where a background launch's stdout/stderr lands. A temp path, not the repo, so a
# launch never leaves an untracked log in the public tree.
typeset -g _THERIA_LOG="${${TMPDIR:-/tmp}%/}/theria-run.log"

# ── shared primitives ────────────────────────────────────────────────────────
# red/yellow to stderr, green to stdout — same idiom as the FlashOS helpers.
_theria_err()  { print -u2 -- "${_THERIA_RED}$*${_THERIA_NC}"; }
_theria_warn() { print -u2 -- "${_THERIA_YELLOW}$*${_THERIA_NC}"; }
_theria_ok()   { print    -- "${_THERIA_GREEN}$*${_THERIA_NC}"; }

# Echo the godot binary path on stdout, or error on stderr. Honors $THERIA_GODOT
# verbatim, then PATH, then the Homebrew default the skill falls back to.
_theria_godot() {
  emulate -L zsh
  local bin="${THERIA_GODOT:-$(command -v godot 2>/dev/null)}"
  [[ -n "$bin" ]] || bin=/opt/homebrew/bin/godot
  if [[ ! -x "$bin" ]]; then
    _theria_err "godot binary not found ($bin) — set \$THERIA_GODOT"
    return 1
  fi
  print -r -- "$bin"
}

# Stop with a clear message if the binary or the project is missing (wrong machine /
# moved tree), so a launch never half-starts.
_theria_verify() {
  emulate -L zsh
  _theria_godot >/dev/null || return 1
  if [[ ! -f "$_THERIA_DIR/project.godot" ]]; then
    _theria_err "no project.godot at $_THERIA_DIR"
    return 1
  fi
}

# Refresh the import / global-class cache (foreground, wait for it). A run started
# right after a new `class_name` script was added otherwise fails to register it.
_theria_import() {
  emulate -L zsh
  local godot; godot="$(_theria_godot)" || return 1
  _theria_ok "refreshing import / class cache…"
  if ! "$godot" --headless --path "$_THERIA_DIR" --import >/dev/null 2>&1; then
    _theria_warn "import pass reported a problem — launching anyway"
  fi
}

# Launch windowed in the background (the terminal stays free), logging to
# $_THERIA_LOG. Everything in argv is forwarded to the game after a bare `--`.
# Imports first unless $THERIA_NO_IMPORT is set. After launch it waits a beat and
# checks the process is still alive — a parse error or missing-asset boot dies
# immediately, so the log tail is surfaced instead of declaring success blindly.
_theria_launch() {
  emulate -L zsh
  _theria_verify || return 1
  [[ -n "$THERIA_NO_IMPORT" ]] || _theria_import || return 1
  local godot; godot="$(_theria_godot)" || return 1
  local label="connect menu"
  (( $# > 0 )) && label="$*"
  _theria_ok "launching theria: ${label}"
  # `&!` backgrounds AND disowns, so the client outlives this function without a
  # job-table entry; $! still holds its pid for the liveness check + `run stop`.
  nohup "$godot" --path "$_THERIA_DIR" -- "$@" >| "$_THERIA_LOG" 2>&1 &!
  local pid=$!
  sleep 2
  if ! kill -0 "$pid" 2>/dev/null; then
    _theria_err "client exited immediately — boot failed. Log tail:"
    tail -n 20 "$_THERIA_LOG" >&2
    return 1
  fi
  _theria_ok "running (pid ${pid}) — window opening. logs: $_THERIA_LOG"
  print -- "stop with: run stop   ·   logs: run log"
}

# Build the launch flags from the dispatcher args, mirroring the skill: no args →
# connect menu; a leading `--flag` → pass everything through; otherwise the first
# bare word is a hero and starts a LOCAL practice match as it, keeping later flags.
_theria_launch_from_args() {
  emulate -L zsh
  local -a flags
  if (( $# == 0 )); then
    flags=()
  elif [[ "$1" == --* ]]; then
    flags=("$@")
  else
    flags=(--local --hero "$1"); shift; flags+=("$@")
  fi
  _theria_launch "${flags[@]}"
}

# Stop the running client (matches the windowed launch by its --path argument).
_theria_stop() {
  emulate -L zsh
  if pkill -f "godot.*--path ${_THERIA_DIR}" 2>/dev/null; then
    _theria_ok "stopped the running theria client"
  else
    _theria_warn "no running theria client found"
  fi
}

# Show the last N lines of the most recent launch log (default 40).
_theria_log() {
  emulate -L zsh
  if [[ ! -s "$_THERIA_LOG" ]]; then
    _theria_warn "no launch log yet: $_THERIA_LOG"
    return 1
  fi
  tail -n "${1:-40}" "$_THERIA_LOG"
}

_theria_usage() {
  print -- "usage: run [hero | --flags | <verb>]"
  print -- "  (no args)                launch to the connect menu (Practice/Host/Join)"
  print -- "  <hero> [flags]           local practice as <hero> (${_THERIA_HEROES})"
  print -- "  --host | --join <addr> | --local | --bot-difficulty easy|normal|hard | --netsim l,j,loss"
  print -- "                           pass flags straight to the client"
  print -- "  menu                     explicit connect menu"
  print -- "  import                   refresh Godot import / global-class cache"
  print -- "  stop                     stop the running client"
  print -- "  log [N]                  last N lines of the launch log (default 40)"
  print -- "  help                     this text"
  print -- "env: THERIA_GODOT=<path>   override the godot binary"
  print -- "     THERIA_NO_IMPORT=1    skip the pre-launch import refresh"
}

# run <verb|hero|--flags> — the single public entry point (named like FlashOS's
# `run`). Reserved verbs win; no hero shares a name with one, so a bare hero word
# still launches a practice match.
run() {
  emulate -L zsh
  case "${1:-}" in
    stop)           _theria_stop ;;
    import)         _theria_verify && _theria_import ;;
    log)            shift; _theria_log "$@" ;;
    menu)           _theria_launch ;;
    help|-h|--help) _theria_usage ;;
    *)              _theria_launch_from_args "$@" ;;
  esac
}

# ── completion ────────────────────────────────────────────────────────────────
# zsh tab-completion for the `run` dispatcher: first arg offers the heroes, the
# verbs, and the passthrough flags; `--join`/`--bot-difficulty` then suggest values.
_theria_completion() {
  local -a verbs flags
  verbs=(
    'menu:connect menu (Practice/Host/Join)'
    'import:refresh Godot import / class cache'
    'stop:stop the running client'
    'log:tail the last launch log'
    'help:usage'
  )
  flags=(
    '--local:local practice match'
    '--host:host a listen-server'
    '--join:join a server by address'
    '--bot-difficulty:set bot skill'
    '--netsim:shape the link (latency,jitter,loss)'
    '--no-update:skip the updater'
  )
  if (( CURRENT == 2 )); then
    _describe -t heroes 'hero' _THERIA_HEROES
    _describe -t verbs 'verb' verbs
    _describe -t flags 'flag' flags
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      --bot-difficulty) _values 'difficulty' easy normal hard ;;
      --join)           _message 'server address (host or ip)' ;;
    esac
  fi
}

if (( $+functions[compdef] )); then
  compdef _theria_completion run
fi
