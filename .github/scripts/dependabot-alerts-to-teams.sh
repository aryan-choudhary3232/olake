#!/usr/bin/env bash
# Posts Dependabot alert changes to a Teams channel:
#   - new vulnerability alerts and new malware alerts
#   - alerts closed by an auto-triage rule (auto_dismissed)
#   - alerts that get fixed, dismissed by hand, or reopened
#
# State lives in $STATE_DIR/state.tsv as "<alert number>\t<state>" lines and is
# kept between runs by the workflow cache. A change is posted once; a failed post
# is retried on the next run.
#
# Env: GH_TOKEN, TEAMS_WEBHOOK_URL, REPO, NOTIFY_EXISTING, CACHE_HIT, MAX_POSTS
set -euo pipefail

if [ -z "${GH_TOKEN:-}" ] || [ -z "${TEAMS_WEBHOOK_URL:-}" ]; then
  echo "::error::DEPENDABOT_READ_TOKEN or TEAMS_WEBHOOK_URL secret is missing"
  exit 1
fi

STATE_DIR=.dependabot-state
state="$STATE_DIR/state.tsv"
mkdir -p "$STATE_DIR"

# Older versions of this job stored only open alert numbers in seen.txt.
migrating=false
if [ ! -f "$state" ] && [ -f "$STATE_DIR/seen.txt" ]; then
  cp "$STATE_DIR/seen.txt" "$state"
  migrating=true
fi
touch "$state"

# Ask for every state and both classifications, so malware and auto-dismissed
# alerts are included.
gh api --paginate \
  "repos/${REPO}/dependabot/alerts?state=open,fixed,dismissed,auto_dismissed&classification=general,malware&per_page=100" \
  --jq '.[]' | jq -s '.' > alerts.json
echo "Alerts (all states): $(jq 'length' alerts.json)"

post() {
  curl -sS --fail-with-body -X POST -H "Content-Type: application/json" \
    -d "$1" "$TEAMS_WEBHOOK_URL" > /dev/null
}

# Wraps {body, actions} into a Teams Adaptive Card message.
JQ_WRAP='{
  type: "message",
  attachments: [{
    contentType: "application/vnd.microsoft.card.adaptive",
    contentUrl: null,
    content: ({"$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
               type: "AdaptiveCard", version: "1.4"} + .)
  }]
}'

# First run without a cache: remember every alert and post one summary, so the
# channel is not flooded with old alerts.
if [ "${CACHE_HIT}" != "true" ] && [ "${NOTIFY_EXISTING}" != "true" ]; then
  jq -r '.[] | "\(.number)\t\(.state)"' alerts.json > "$state"
  summary=$(jq -c --arg repo "$REPO" '
    def open_of(c): map(select(.state == "open" and ((.security_advisory.classification // "general") == c))) | length;
    {
      body: [
        {type: "TextBlock", size: "Medium", weight: "Bolder", text: "Dependabot alerts connected"},
        {type: "TextBlock", wrap: true,
         text: ("Watching **" + $repo + "**. New, malware, auto-dismissed, fixed and dismissed alerts will be posted here.")},
        {type: "FactSet", facts: [
          {title: "Open vulnerability alerts", value: (open_of("general") | tostring)},
          {title: "Open malware alerts", value: (open_of("malware") | tostring)},
          {title: "Auto-dismissed", value: (map(select(.state == "auto_dismissed")) | length | tostring)}
        ]}
      ],
      actions: [{type: "Action.OpenUrl", title: "View alerts",
                 url: ("https://github.com/" + $repo + "/security/dependabot")}]
    }' alerts.json | jq -c "$JQ_WRAP")
  post "$summary"
  echo "Seeded $(wc -l < "$state" | tr -d ' ') alerts"
  exit 0
fi

# prev.json: alert number -> last posted state.
jq -Rn '[inputs | select(length > 0) | split("\t") | {key: .[0], value: (.[1] // "open")}] | from_entries' \
  "$state" > prev.json

if [ "${NOTIFY_EXISTING}" = "true" ]; then
  # Re-post every open alert; do not replay closed history.
  jq '[.[] | select(.state != "open") | {key: (.number | tostring), value: .state}] | from_entries' \
    alerts.json > prev.json
elif [ "$migrating" = "true" ]; then
  # seen.txt only knew open alerts. Treat closed alerts it never saw as already posted.
  jq --slurpfile p prev.json \
    '([.[] | select(.state != "open") | {key: (.number | tostring), value: .state}] | from_entries) + $p[0]' \
    alerts.json > prev.tmp && mv prev.tmp prev.json
fi

# One line per alert whose state differs from what was last posted.
jq -c --slurpfile p prev.json '
  $p[0] as $prev | sort_by(.number) | .[]
  | (.number | tostring) as $k
  | select($prev[$k] != .state)
  | . + {prev_state: $prev[$k]}' alerts.json > events.jsonl
echo "Changes to post: $(wc -l < events.jsonl | tr -d ' ')"

: > posted.txt
posted=0
while IFS= read -r ev; do
  [ -z "$ev" ] && continue
  if [ "$posted" -ge "$MAX_POSTS" ]; then
    echo "Hit MAX_POSTS=${MAX_POSTS}; the rest go out on the next run"
    break
  fi

  card=$(jq -c --arg repo "$REPO" '
    (.security_advisory.severity // "unknown") as $sev
    | ((.security_advisory.classification // "general") == "malware") as $mal
    | (if .prev_state == null then
         {open: "New", auto_dismissed: "Auto-dismissed", fixed: "New (already fixed)",
          dismissed: "New (already dismissed)"}[.state]
       else
         {open: "Reopened", auto_dismissed: "Auto-dismissed", fixed: "Fixed",
          dismissed: "Dismissed"}[.state]
       end) as $what
    | (if .state == "open" then
         (if $mal or $sev == "critical" or $sev == "high" then "Attention"
          elif $sev == "medium" then "Warning" else "Default" end)
       elif .state == "fixed" then "Good" else "Default" end) as $color
    | {
        body: ([
          {type: "TextBlock", size: "Medium", weight: "Bolder", wrap: true, color: $color,
           text: ($what + " " + (if $mal then "MALWARE alert" else "Dependabot alert" end)
                  + " #" + (.number | tostring) + ": " + ($sev | ascii_upcase))},
          {type: "TextBlock", wrap: true, text: (.security_advisory.summary // "No summary")}
        ]
        + (if $mal and .state == "open" then
             [{type: "TextBlock", wrap: true, weight: "Bolder", color: "Attention",
               text: "This package is known malware. Remove it and rotate any secrets the build could reach."}]
           else [] end)
        + (if .state == "auto_dismissed" then
             [{type: "TextBlock", wrap: true, isSubtle: true,
               text: "Closed by a Dependabot auto-triage rule. Reopen it on GitHub if the rule should not apply."}]
           else [] end)
        + [{type: "FactSet", facts: ([
            {title: "Repository", value: $repo},
            {title: "State", value: .state},
            {title: "Package", value: ((.dependency.package.name // "?") + " (" + (.dependency.package.ecosystem // "?") + ")")},
            {title: "Manifest", value: (.dependency.manifest_path // "?")},
            {title: "Scope", value: (.dependency.scope // "?")},
            {title: "Vulnerable", value: (.security_vulnerability.vulnerable_version_range // "?")},
            {title: "Fixed in", value: (.security_vulnerability.first_patched_version.identifier // "no fix yet")},
            {title: "Advisory", value: (.security_advisory.ghsa_id // "?")},
            {title: "CVE", value: (.security_advisory.cve_id // "none")}
          ]
          + (if .state == "dismissed" then
               [{title: "Dismissed by", value: (.dismissed_by.login // "?")},
                {title: "Reason", value: ((.dismissed_reason // "?") + (if .dismissed_comment then ": " + .dismissed_comment else "" end))}]
             else [] end))}]),
        actions: [{type: "Action.OpenUrl", title: "Open alert", url: .html_url}]
      }' <<< "$ev" | jq -c "$JQ_WRAP")

  num=$(jq -r '.number' <<< "$ev")
  st=$(jq -r '.state' <<< "$ev")
  if post "$card"; then
    echo "$num" >> posted.txt
    posted=$((posted + 1))
    echo "Posted alert #${num} (${st})"
  else
    echo "::warning::Failed to post alert #${num}; will retry next run"
  fi
  sleep 1
done < events.jsonl

# Save the posted state. Alerts not posted this run keep their old state, so
# they are retried next run.
jq -r --slurpfile p prev.json --rawfile done posted.txt '
  $p[0] as $prev
  | ($done | split("\n") | map(select(length > 0))) as $posted
  | .[] | (.number | tostring) as $k
  | if $prev[$k] == .state or ($posted | any(. == $k)) then "\($k)\t\(.state)"
    elif $prev[$k] then "\($k)\t\($prev[$k])"
    else empty end' alerts.json > "$state"
rm -f "$STATE_DIR/seen.txt"

echo "Posted ${posted} change(s)"
