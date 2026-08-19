#!/usr/bin/env bash
# Configure this repository to use its versioned hook directory.

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
source "${root}/scripts/bounded-command.sh"
readonly hooks_path="scripts/git-hooks"

repository_root="$(utexo_capture_quick git -C "${root}" rev-parse --show-toplevel)"
readonly repository_root
[[ "${repository_root}" == "${root}" ]] || {
  printf 'Could not establish the expected repository root.\n' >&2
  exit 1
}

set +e
current="$(
  utexo_capture_quick git -C "${root}" config --local --get core.hooksPath
)"
current_status=$?
set -e
((current_status == 0 || current_status == 1)) || exit "${current_status}"
readonly current

if [[ ! -x "${root}/${hooks_path}/pre-commit" ]]; then
  printf 'Versioned pre-commit hook is missing or not executable.\n' >&2
  exit 1
fi

if [[ -n "${current}" && "${current}" != "${hooks_path}" ]]; then
  printf 'Refusing to replace existing local core.hooksPath: %s\n' \
    "${current}" >&2
  exit 1
fi

utexo_run_quick git -C "${root}" config --local core.hooksPath "${hooks_path}"
printf 'Git hooks path configured for this repository: %s\n' "${hooks_path}"
