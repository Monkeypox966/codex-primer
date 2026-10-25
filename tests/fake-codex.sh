#!/bin/bash
# CI-only replacement used on the disposable integration host. No networking.
set -euo pipefail
task_mode=$(cat /var/lib/codex-primer/test-mode 2>/dev/null || printf success)
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'codex-cli 0.164.0'
elif [[ ${1:-} == login && ${2:-} == status ]]; then
  if [[ $task_mode == login-timeout ]]; then sleep 60; fi
  if [[ $task_mode == api-key ]]; then printf '%s\n' 'Logged in using an API key'; else printf '%s\n' 'Logged in using ChatGPT'; fi
  if [[ $task_mode == login-failure ]]; then exit 31; fi
elif [[ ${1:-} == exec ]]; then
  printf '%s\n' "$task_mode" >>/var/lib/codex-primer/exec-attempts
  if [[ -n ${OPENAI_API_KEY:-}${CODEX_API_KEY:-}${CODEX_ACCESS_TOKEN:-}${CODEX_HOME:-} ]]; then
    printf '%s\n' 'Inherited credentials were not cleared.' >&2
    exit 99
  fi
  task_reply_file=
  while (($#)); do
    if [[ $1 == --output-last-message ]]; then task_reply_file=$2; shift 2; else shift; fi
  done
  [[ -n $task_reply_file ]]
  case "$task_mode" in
    success) printf 'OK\n' >"$task_reply_file"; printf '%s\n' '{"type":"turn.completed"}' ;;
    empty-reply) : ;;
    wrong-reply) printf 'Unexpected\n' >"$task_reply_file" ;;
    failure) exit 17 ;;
    *) exit 98 ;;
  esac
else
  exit 97
fi
