#!/usr/bin/env bash
# Runs every script test. Exit status is non-zero if any fails.
cd "$(dirname "${BASH_SOURCE[0]}")"
failed=0
for suite in test_placeholders.sh test_lock_files.sh test_start.sh test_init.sh test_roles.sh; do
  echo "################ ${suite}"
  bash "./${suite}" < /dev/null || failed=1
done
[[ ${failed} -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit ${failed}
