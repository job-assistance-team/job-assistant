#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_EVENT_NAME:?}"
: "${GITHUB_EVENT_PATH:?}"

field() {
  jq -r "($1 // \"\") | tostring | @html" "$GITHUB_EVENT_PATH"
}

link() {
  printf '<a href="%s">#%s %s</a>' "$(field "$1.html_url")" "$(field "$1.number")" "$(field "$1.title")"
}

build_message() {
  local action actor
  action=$(field '.action')
  actor=$(field '.sender.login')

  case "$GITHUB_EVENT_NAME:$action" in
    issues:opened)    printf 'New issue by %s\n%s' "$actor" "$(link .issue)" ;;
    issues:assigned)  printf 'Issue assigned to %s\n%s' "$(field '.assignee.login')" "$(link .issue)" ;;
    issues:closed)    printf 'Issue closed by %s\n%s' "$actor" "$(link .issue)" ;;
    issues:reopened)  printf 'Issue reopened by %s\n%s' "$actor" "$(link .issue)" ;;

    pull_request:opened)
      printf 'New PR by %s\n%s' "$actor" "$(link .pull_request)" ;;
    pull_request:review_requested)
      printf 'Review requested from %s\n%s' "$(field '.requested_reviewer.login')" "$(link .pull_request)" ;;
    pull_request:closed)
      if [[ $(field '.pull_request.merged') == true ]]; then
        printf 'PR merged by %s\n%s' "$actor" "$(link .pull_request)"
      else
        printf 'PR closed without merge\n%s' "$(link .pull_request)"
      fi
      ;;

    pull_request_review:submitted)
      case $(field '.review.state') in
        approved)          printf '%s approved\n%s' "$actor" "$(link .pull_request)" ;;
        changes_requested) printf '%s requested changes\n%s' "$actor" "$(link .pull_request)" ;;
        commented)         printf '%s left a review\n%s' "$actor" "$(link .pull_request)" ;;
      esac
      ;;
  esac
}

send_message() {
  jq -n --arg chat_id "$TELEGRAM_CHAT_ID" --arg text "$1" \
    '{chat_id: $chat_id, text: $text, parse_mode: "HTML", disable_web_page_preview: true}' |
    curl -sS --fail-with-body --retry 3 --max-time 10 \
      -H 'Content-Type: application/json' -d @- \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null
}

message=$(build_message)

if [[ -z $message ]]; then
  echo "skip: $GITHUB_EVENT_NAME"
  exit 0
fi

if [[ ${DRY_RUN:-} == 1 ]]; then
  echo "$message"
  exit 0
fi

# secrets are not passed to workflows from forks
if [[ -z ${TELEGRAM_BOT_TOKEN:-} || -z ${TELEGRAM_CHAT_ID:-} ]]; then
  echo "skip: telegram credentials not set"
  exit 0
fi

send_message "$message"
