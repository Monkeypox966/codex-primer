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

task_started_seconds=$SECONDS
task_started_at=$(/usr/bin/date -u +%FT%TZ)
task_reply=
task_outcome=interrupted
# Called indirectly by the EXIT trap, including early login failures.
# shellcheck disable=SC2329
finish_request() {
  local task_status=$? task_peak_bytes=null task_record task_finished_at task_duration
  [[ -z $task_reply ]] || rm -f -- "$task_reply"
  if [[ -r /sys/fs/cgroup/system.slice/codex-primer.service/memory.peak ]]; then
    read -r task_peak_bytes </sys/fs/cgroup/system.slice/codex-primer.service/memory.peak
    [[ $task_peak_bytes =~ ^[0-9]+$ ]] || task_peak_bytes=null
    printf 'Service peak memory: %s bytes\n' "$task_peak_bytes"
  fi
  task_finished_at=$(/usr/bin/date -u +%FT%TZ)
  task_duration=$((SECONDS - task_started_seconds))
  if task_record=$(mktemp /var/lib/codex-primer/.last-run.XXXXXXXX); then
    if ! printf '{"startedAt":"%s","finishedAt":"%s","durationSeconds":%s,"exitCode":%s,"outcome":"%s","peakMemoryBytes":%s}\n' \
      "$task_started_at" "$task_finished_at" "$task_duration" "$task_status" "$task_outcome" "$task_peak_bytes" >"$task_record" ||
      ! mv -f -- "$task_record" /var/lib/codex-primer/last-run.json; then
      rm -f -- "$task_record"
      printf '%s\n' 'Could not save the last request summary.' >&2
    fi
  else
    printf '%s\n' 'Could not create the last request summary.' >&2
  fi
  printf 'Finished: %s; exit=%s; outcome=%s; elapsed=%ss\n' "$task_finished_at" "$task_status" "$task_outcome" "$task_duration"
}
trap 'finish_request' EXIT

task_outcome=login-failed
task_login_status=$(/usr/bin/timeout --signal=TERM --kill-after=2s 5s \
  /opt/codex-primer/bin/codex-x86_64-unknown-linux-musl login status 2>&1) || {
  printf '%s\n' 'Cannot read the ChatGPT subscription login; no request was sent.' >&2
  exit 1
}
if [[ $task_login_status != *'Logged in using ChatGPT'* ]]; then
  task_outcome=wrong-auth
  printf '%s\n' 'No ChatGPT subscription login; refusing to send a request.' >&2
  exit 1
fi
task_reply=$(mktemp) || exit 1
task_outcome=command-failed
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
  task_outcome=reply-mismatch
  printf '%s\n' 'Request exited without the expected final OK reply.' >&2
  task_status=1
fi
if ((task_status == 0)); then
  task_outcome=success
elif ((task_status == 124 || task_status == 137)); then
  task_outcome=timeout
fi
exit "$task_status"
