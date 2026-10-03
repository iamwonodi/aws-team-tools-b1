#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# EVERY ROOT CONFIGURATION HAS A COMMITTED, COMPLETE PROVIDER LOCK FILE
#
# The lock file pins the exact provider builds and their checksums, so every
# plan and apply -- on a laptop or in CI -- installs the same providers. It only
# works if it is committed, and it is easy to forget: `terraform init` writes it
# locally and nothing complains that it is untracked.
#
# For each directory given, this fails unless:
#   - .terraform.lock.hcl is tracked by git, and
#   - it lists every provider the directory's own required_providers declares, and
#   - every provider in it has at least MIN_H1 "h1:" hashes, one per locked
#     platform. A plain `terraform init` records only the machine's own platform,
#     which passes locally and fails `terraform init -lockfile=readonly` or
#     `terraform validate` in CI on Linux.
#
# Providers that only child modules declare are checked by Terraform itself: the
# workflows run `terraform init -lockfile=readonly`, which refuses a lock file
# that does not cover the whole configuration.
#
# Usage: check-lock-files.sh <root-dir>...
# ==============================================================================

[[ $# -gt 0 ]] || { echo "Usage: check-lock-files.sh <root-dir>..." >&2; exit 1; }

LOCK_COMMAND='terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64'
MIN_H1=4
FAILED=0

for DIR in "$@"; do
  DIR="${DIR%/}"
  LOCK="${DIR}/.terraform.lock.hcl"

  if [[ ! -f "${LOCK}" ]]; then
    echo "::error file=${DIR}::${LOCK} does not exist. Run 'terraform -chdir=${DIR} init' and then '${LOCK_COMMAND}' in that folder, and commit it."
    FAILED=1
    continue
  fi

  if ! git ls-files --error-unmatch "${LOCK}" >/dev/null 2>&1; then
    echo "::error file=${LOCK}::${LOCK} exists but is not committed. git add it."
    FAILED=1
    continue
  fi

  # Providers this root declares itself, as <namespace>/<type>.
  DECLARED="$(cat "${DIR}"/*.tf 2>/dev/null \
    | grep -oE 'source[[:space:]]*=[[:space:]]*"[a-z0-9-]+/[a-z0-9-]+"' \
    | sed -E 's/.*"([^"]+)"/\1/' | sort -u || true)"

  MISSING=()
  for PROVIDER in ${DECLARED}; do
    grep -q "provider \"registry.terraform.io/${PROVIDER}\"" "${LOCK}" || MISSING+=("${PROVIDER}")
  done

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "::error file=${LOCK}::${LOCK} does not lock ${MISSING[*]}. Run 'terraform -chdir=${DIR} init -upgrade', then '${LOCK_COMMAND}' there, and commit it."
    FAILED=1
    continue
  fi

  # "h1:" hashes per provider block: one per platform locked.
  THIN=()
  while read -r NAME COUNT; do
    [[ "${COUNT}" -ge "${MIN_H1}" ]] || THIN+=("${NAME} has ${COUNT}")
  done < <(awk '
    /^provider "/ { name = $2; gsub(/"/, "", name); sub(/^registry\.terraform\.io\//, "", name); count = 0; inside = 1; next }
    inside && /"h1:/ { count++ }
    inside && /^}/ { print name, count; inside = 0 }
  ' "${LOCK}")

  if [[ ${#THIN[@]} -gt 0 ]]; then
    echo "::error file=${LOCK}::${LOCK} must carry at least ${MIN_H1} h1: hashes per provider (one per platform), but ${THIN[*]}. Run '${LOCK_COMMAND}' in ${DIR}, and commit it."
    FAILED=1
    continue
  fi

  echo "ok   ${LOCK}"
done

exit "${FAILED}"
