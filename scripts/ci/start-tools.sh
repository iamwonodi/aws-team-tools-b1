#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# START THE TEAM TOOLS NOW (the Start tools workflow)
#
# Sets the tools' Auto Scaling group to one server. Outside the schedule it also
# books a one-off stop two hours later -- unless those two hours reach into the
# schedule, whose own stop then applies (a stop booked inside the schedule would
# switch the tools off in the middle of the day). Pressing it again moves the
# booked stop to two hours from then.
#
# The schedule is tools/schedule.json, the same file Terraform builds the
# recurring actions from, in Lagos time.
#
# Usage: start-tools.sh <environment> <project> <aws-region>
#   TOOLS_NOW  (tests) the current time, "YYYY-MM-DD HH:MM" Lagos time
# ==============================================================================

ENVIRONMENT="${1:?Usage: start-tools.sh <environment> <project> <aws-region>}"
PROJECT="${2:?project is required}"
REGION="${3:?aws-region is required}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEDULE_FILE="${REPO_ROOT}/tools/schedule.json"
STOP_ACTION="manual-stop"
RUN_HOURS=2

case "${ENVIRONMENT}" in
  development|staging|production) ;;
  *) echo "ERROR: '${ENVIRONMENT}' is not an environment: development, staging or production." >&2; exit 1 ;;
esac
[[ "${PROJECT}" =~ ^[a-z][a-z0-9-]{1,14}[a-z0-9]$ ]] || { echo "ERROR: '${PROJECT}' is not a project name." >&2; exit 1; }

DAYS="$(jq -er --arg e "${ENVIRONMENT}" '.[$e].days' "${SCHEDULE_FILE}")"
START_HOUR="$(jq -er --arg e "${ENVIRONMENT}" '.[$e].start_hour' "${SCHEDULE_FILE}")"
STOP_HOUR="$(jq -er --arg e "${ENVIRONMENT}" '.[$e].stop_hour' "${SCHEDULE_FILE}")"

case "${DAYS}" in
  MON-FRI) SCHEDULED_DAYS="1 2 3 4 5" ;;
  SAT,SUN) SCHEDULED_DAYS="6 7" ;;
  *) echo "ERROR: tools/schedule.json has days '${DAYS}' for ${ENVIRONMENT}; expected MON-FRI or SAT,SUN." >&2; exit 1 ;;
esac

ASG="${PROJECT}-${ENVIRONMENT}-team-tools-asg"
NOW="${TOOLS_NOW:-$(TZ=Africa/Lagos date '+%Y-%m-%d %H:%M')}"

# Whether a moment, "YYYY-MM-DD HH:MM" Lagos time, falls inside the schedule.
in_schedule() {
  local day hour
  day="$(TZ=Africa/Lagos date -d "$1" '+%u')"
  hour="$(TZ=Africa/Lagos date -d "$1" '+%-H')"
  [[ " ${SCHEDULED_DAYS} " == *" ${day} "* ]] && (( hour >= START_HOUR && hour < STOP_HOUR ))
}

STOP_AT_LAGOS="$(TZ=Africa/Lagos date -d "${NOW} ${RUN_HOURS} hours" '+%Y-%m-%d %H:%M')"

echo "Starting the team tools in ${ENVIRONMENT} (${ASG})."
aws autoscaling set-desired-capacity --region "${REGION}" \
  --auto-scaling-group-name "${ASG}" --desired-capacity 1

if in_schedule "${NOW}"; then
  echo "It is within the schedule (${DAYS} ${START_HOUR}:00-${STOP_HOUR}:00 Lagos): the tools stop at ${STOP_HOUR}:00."
  exit 0
fi

if in_schedule "${STOP_AT_LAGOS}"; then
  # The schedule takes over before two hours are up; an earlier booked stop
  # would now fall inside it, so it goes.
  aws autoscaling delete-scheduled-action --region "${REGION}" \
    --auto-scaling-group-name "${ASG}" --scheduled-action-name "${STOP_ACTION}" 2>/dev/null || true
  echo "The schedule starts within ${RUN_HOURS} hours: the tools run on and stop at ${STOP_HOUR}:00 as scheduled."
  exit 0
fi

# Through a timestamp, which has no time zone: with -u, date would also read
# the Lagos time as UTC.
STOP_AT_EPOCH="$(TZ=Africa/Lagos date -d "${STOP_AT_LAGOS}" '+%s')"
STOP_AT_UTC="$(date -u -d "@${STOP_AT_EPOCH}" '+%Y-%m-%dT%H:%M:%SZ')"

aws autoscaling put-scheduled-update-group-action --region "${REGION}" \
  --auto-scaling-group-name "${ASG}" --scheduled-action-name "${STOP_ACTION}" \
  --start-time "${STOP_AT_UTC}" --min-size 0 --max-size 1 --desired-capacity 0

echo "The tools switch off at ${STOP_AT_LAGOS} Lagos time (${STOP_AT_UTC})."
