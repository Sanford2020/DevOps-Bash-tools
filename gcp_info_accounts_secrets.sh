#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-08-13 19:38:39 +0100 (Thu, 13 Aug 2020)
#
#  https://github.com/harisekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
. "$srcdir/lib/utils.sh"

# shellcheck disable=SC1090
. "$srcdir/lib/gcp.sh"

# shellcheck disable=SC2034,SC2154
usage_description="
Lists GCP IAM Service Accounts & Secrets Manager secrets deployed in the current GCP Project

Lists in this order:

    - IAM Service Accounts
    - Secrets Manager secrets

$gcp_info_formatting_help
"

# used by usage() in lib/utils.sh
# shellcheck disable=SC2034
usage_args=""

help_usage "$@"


# shellcheck disable=SC1090
type is_service_enabled &>/dev/null || . "$srcdir/gcp_service_apis.sh" >/dev/null


# Service Accounts
cat <<EOF
# ============================================================================ #
#                        S e r v i c e   A c c o u n t s
# ============================================================================ #

EOF

gcp_info "Service Accounts" gcloud iam service-accounts list


# Secrets
cat <<EOF


# ============================================================================ #
#                                 S e c r e t s
# ============================================================================ #

EOF

if is_service_enabled secretmanager.googleapis.com; then
    gcp_info "GCP Secrets" gcloud secrets list
else
    echo "Secrets Manager API (secretmanager.googleapis.com) is not enabled, skipping..."
fi
