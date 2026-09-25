#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
INIT="${SCRIPTS}/init-tools.sh"
SOURCE_ROOT="$(cd "${SCRIPTS}/.." && pwd)"
export FAKE_GH_REPO_JSON='{"id":987,"owner":{"id":123}}'

fresh(){
  rm -rf "${WORK}/repo"; mkdir -p "${WORK}/repo/scripts/ci" "${WORK}/repo/infrastructure"
  for e in development staging production; do cp -r "${SOURCE_ROOT}/infrastructure/$e" "${WORK}/repo/infrastructure/"; rm -rf "${WORK}/repo/infrastructure/$e/.terraform"; done
  cp "${SCRIPTS}/ci/check-placeholders.sh" "${SCRIPTS}/ci/enabled-environments.sh" "${WORK}/repo/scripts/ci/"
  mkdir -p "${WORK}/repo/.github"; echo '["development","staging","production"]' > "${WORK}/repo/.github/environments.json"
  git -C "${WORK}/repo" init -q; git -C "${WORK}/repo" remote add origin https://github.com/acme/team-tools.git
  export INIT_REPO_ROOT="${WORK}/repo" FAKE_GH_LOG="${WORK}/gh.log"; : > "${FAKE_GH_LOG}"
}
I="${WORK}/repo/infrastructure"
run(){ bash "${INIT}" --project acme --region af-south-1 "$@"; }

echo "== init-tools.sh"
fresh; run --reviewers alice > "${WORK}/out.txt" 2>&1; rc=$?
check "run succeeds"                                       test $rc -eq 0
for e in development staging production; do
  check "$e: project and region are set"                   bash -c "grep -qx 'project_name = \"acme\"' '$I/$e/terraform.tfvars' && grep -qx 'aws_region   = \"af-south-1\"' '$I/$e/terraform.tfvars'"
  check "$e: its own state bucket"                         grep -q "bucket = \"acme-$e-tfstate\"" "$I/$e/backend.tf"
  check "$e: the state key keeps core's prefix"            grep -q 'key = "team-tools/terraform.tfstate"' "$I/$e/backend.tf"
  check "$e: no placeholder remains"                       bash "${WORK}/repo/scripts/ci/check-placeholders.sh" "$I/$e"
  check "$e: its environment is main-only, reviewed"       bash -c "grep -A1 'environments/$e --input' '${FAKE_GH_LOG}' | grep -q 'custom_branch_policies\":true' && grep -A1 'environments/$e --input' '${FAKE_GH_LOG}' | grep -q '\"id\":4242'"
  check "$e: and its plan environment exists"              grep -q "environments/$e-plan --input" "${FAKE_GH_LOG}"
done
check "AWS_REGION is set on all six environments"          bash -c "[ \$(grep -c 'variable set AWS_REGION --repo acme/team-tools' '${FAKE_GH_LOG}') -eq 6 ]"
check "core's tfvars lines are printed with the IDs"       bash -c "grep -q 'team_tools_repository          = \"acme/team-tools\"' '${WORK}/out.txt' && grep -q 'owner_id = \"123\"' '${WORK}/out.txt' && grep -q 'repository_id       = \"987\"' '${WORK}/out.txt'"
fresh; run >/dev/null 2>&1; run > "${WORK}/out2.txt" 2>&1
check "re-running is safe"                                 bash -c "[ \$? -eq 0 ] && grep -qx 'project_name = \"acme\"' '$I/staging/terraform.tfvars'"
check "no reviewers is warned about"                       grep -q 'WARNING: no --reviewers' "${WORK}/out2.txt"
fresh; run --dry-run >/dev/null 2>&1
check "a dry run writes nothing"                           grep -q 'CHANGE_ME' "$I/production/terraform.tfvars"
check "and calls no GitHub"                                bash -c "[ ! -s '${FAKE_GH_LOG}' ]"
fresh; run --skip-github >/dev/null 2>&1
check "--skip-github writes the files only"                bash -c "grep -qx 'project_name = \"acme\"' '$I/development/terraform.tfvars' && [ ! -s '${FAKE_GH_LOG}' ]"
fresh
check "a bad project is refused"                           bash -c "! bash '${INIT}' --project Acme --region af-south-1 >/dev/null 2>&1"
check "a bad region is refused"                            bash -c "! bash '${INIT}' --project acme --region africa >/dev/null 2>&1"
echo "== environments"
fresh; run --environments production,development --reviewers alice > "${WORK}/out.txt" 2>&1; rc=$?
check "--environments succeeds"                            test $rc -eq 0
check "the list is written, in order"                      bash -c "[ \"\$(jq -c . '${WORK}/repo/.github/environments.json')\" = '[\"development\",\"production\"]' ]"
check "staging's files are left alone"                     grep -q CHANGE_ME "$I/staging/terraform.tfvars"
check "no GitHub Environment for staging"                  bash -c "! grep -q 'environments/staging' '${FAKE_GH_LOG}'"
check "core's lines name only those environments"          grep -q 'run in (development production)' "${WORK}/out.txt"
fresh
check "an unknown --environments is refused"               bash -c "! bash '${INIT}' --project acme --region af-south-1 --environments prod >/dev/null 2>&1"
finish
