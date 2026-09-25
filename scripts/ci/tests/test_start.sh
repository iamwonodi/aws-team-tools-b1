#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="${SCRIPTS}/ci/start-tools.sh"
export PATH="$(dirname "${BASH_SOURCE[0]}")/bin:${PATH}"
export FAKE_AWS_LOG="${WORK}/aws.log"

start(){ : > "${FAKE_AWS_LOG}"; TOOLS_NOW="$2" bash "$S" "$1" acme af-south-1 > "${WORK}/out.txt" 2>&1; }
called(){ grep -q -- "$1" "${FAKE_AWS_LOG}"; }
not_called(){ ! grep -q -- "$1" "${FAKE_AWS_LOG}"; }
all(){ local c; for c in "$@"; do eval "$c" || return 1; done; }

echo "== start-tools.sh"
# 2026-09-23 is a Wednesday, 2026-09-26 a Saturday, 2026-09-27 a Sunday.
start development "2026-09-23 22:00"
check "outside the schedule: one server"                   all "called set-desired-capacity" "called 'auto-scaling-group-name acme-development-team-tools-asg --desired-capacity 1'"
check "and a stop two hours later, in UTC (Lagos is +1)"   called "put-scheduled-update-group-action --region af-south-1 --auto-scaling-group-name acme-development-team-tools-asg --scheduled-action-name manual-stop --start-time 2026-09-23T23:00:00Z --min-size 0 --max-size 1 --desired-capacity 0"

start development "2026-09-23 10:00"
check "inside the schedule: one server"                    called "--desired-capacity 1"
check "and no stop booked: the schedule stops it at 19:00" not_called "put-scheduled-update-group-action"

start development "2026-09-23 07:00"
check "two hours would reach into the schedule: no stop"   not_called "put-scheduled-update-group-action"
check "and an earlier booked stop is cancelled"            called "delete-scheduled-action --region af-south-1 --auto-scaling-group-name acme-development-team-tools-asg --scheduled-action-name manual-stop"

start staging "2026-09-23 10:00"
check "staging runs at weekends: a weekday start stops"    called "--start-time 2026-09-23T11:00:00Z"

start staging "2026-09-26 18:00"
check "staging on Saturday afternoon: its schedule"        not_called "put-scheduled-update-group-action"

start development "2026-09-27 23:30"
check "Sunday night into Monday before 08:00: a stop"      called "--start-time 2026-09-28T00:30:00Z"

start production "2026-09-23 06:30"
check "06:30 + 2h is 08:30, inside: no stop"               not_called "put-scheduled-update-group-action"

: > "${FAKE_AWS_LOG}"
bash "$S" testing acme af-south-1 > /dev/null 2>&1; rc=$?
check "an unknown environment is refused"                  bash -c "[[ $rc -ne 0 ]] && [[ ! -s '${FAKE_AWS_LOG}' ]]"
bash "$S" development "Acme!" af-south-1 > /dev/null 2>&1; rc=$?
check "a project that is not a name is refused"            test $rc -ne 0
finish
