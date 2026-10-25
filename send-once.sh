#!/bin/bash
set -u
umask 077
unset OPENAI_API_KEY CODEX_API_KEY CODEX_ACCESS_TOKEN OPENAI_BASE_URL CODEX_HOME CODEX_SQLITE_HOME

cd /var/lib/codex-primer/work || exit 1
exec 9>/var/lib/codex-primer/send.lock || exit 1
if ! /usr/bin/flock -n 9; then
  printf '%s\n' 'Skipped: previous invocation is still running.'
  exit 0
fi

task_login_status=$(/opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login status 2>&1) || {
  printf '%s\n' 'Cannot read the ChatGPT subscription login; no request was sent.' >&2
  exit 1
}
if [[ $task_login_status != *'Logged in using ChatGPT'* ]]; then
  printf '%s\n' 'No ChatGPT subscription login; refusing to send a request.' >&2
  exit 1
fi
task_reply=$(mktemp) || exit 1
trap 'rm -f -- "$task_reply"' EXIT
printf 'Started: %s; model=gpt-6-luna; one scheduled invocation\n' "$(/usr/bin/date --iso-8601=seconds)"
/usr/bin/timeout --signal=TERM --kill-after=10s 90s \
  /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl exec \
  --ignore-user-config --ephemeral --skip-git-repo-check \
  --sandbox read-only --color never --json --output-last-message "$task_reply" \
  --model gpt-6-luna \
  --disable daemon_auto_start --disable shell_tool \
  --disable apps --disable plugins --disable multi_agent \
  --disable code_mode_host --disable shell_snapshot \
  --disable unbounded_connection_retries --disable skill_search \
  --disable workspace_dependencies --disable browser_use \
  --disable computer_use --disable image_generation --disable in_app_browser \
  -c 'model_reasoning_effort="low"' \
  -c 'model_instructions_file="/opt/codex-primer/instructions.txt"' \
  -c 'project_doc_max_bytes=0' \
  -c 'skills.include_instructions=false' \
  -c 'include_apps_instructions=false' \
  -c 'include_collaboration_mode_instructions=false' \
  -c 'history.persistence="none"' \
  -c 'analytics.enabled=false' \
  -c 'web_search="disabled"' \
  'Reply only OK. Do not use tools.' </dev/null
task_status=$?
if ((task_status == 0)) && [[ $(<"$task_reply") != OK ]]; then
  printf '%s\n' 'Request exited without the expected final OK reply.' >&2
  task_status=1
fi
if test -r /sys/fs/cgroup/system.slice/codex-primer.service/memory.peak; then
  read -r task_peak_bytes </sys/fs/cgroup/system.slice/codex-primer.service/memory.peak
  printf 'Service peak memory: %s bytes\n' "$task_peak_bytes"
fi
printf 'Finished: %s; exit=%s\n' "$(/usr/bin/date --iso-8601=seconds)" "$task_status"
exit "$task_status"
