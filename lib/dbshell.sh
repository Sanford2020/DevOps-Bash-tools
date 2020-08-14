#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#  shellcheck disable=SC2034
#
#  Author: Hari Sekhon
#  Date: 2020-08-05 13:42:41 +0100 (Wed, 05 Aug 2020)
#
#  https://github.com/harisekhon/bash-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# Utility library for the postgres / mysql / mariadb scripts at top level

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sql_scripts="$srcdir/sql"
if [ -d "$srcdir/../sql" ]; then
    sql_scripts="$srcdir/../sql"
fi

sql_mount_description="
SQL  scripts     => /sql  <- session \$PWD for convenient sql sourcing
Bash scripts     => /bash
host \$PWD        => /pwd
\$HOME/github     => /github
"

docker_sql_mount_switches=" \
    -v '$srcdir:/bash' \
    -v '$sql_scripts:/sql' \
    -v '$HOME/github:/github' \
    -v '$PWD:/pwd' \
"

# MySQL 5.5 container
#
# MySQL init process done. Ready for start up.
# ...
# 200808 19:30:58 [Note] mysqld: ready for connections.
wait_for_mysql_ready(){
    local container_name="$1"
    local max_secs=90
    local num_lines=50
    local tries=0
    SECONDS=0
    while true; do
        ((tries+=1))
        if [ $((tries % 5)) = 0 ]; then
            timestamp 'waiting for mysqld to be ready to accept connections before connecting mysql shell...'
        fi
        if docker logs --tail "$num_lines" "$container_name" 2>&1 |
            grep -i -A "$num_lines" \
                 -e 'Entrypoint.*Ready' \
                 -e 'MySQL init process done' |
            grep -q \
                 -e 'mysqld.*ready for connections' \
                 -e 'mysqld.*ready to accept connections'; then
            break
        fi
        sleep 1
        if [ $SECONDS -gt $max_secs ]; then
            timestamp "container '$container_name' failed to become ready for connections within $max_secs secs, check logs (format may have changed):"
            echo >&2
            docker logs "$container_name"
            exit 1
        fi
    done
}

docker_rm_when_last_connection(){
    local scriptname="$1"
    local container_name="$2"
    [ -z "${DOCKER_NO_DELETE:-}" ] || return
    if [ "$(lsof -lnt "$scriptname" | grep -c .)" -lt 2 ]; then
    #if [ "$(pgrep -lf "bash.*${0##*/}" | grep -c .)" -lt 2 ]; then
    #if [ "$(ps -ef | grep -c "[b]ash.*${0##*/}")" -lt 2 ]; then
        timestamp "last session closing, deleting container:"
        docker rm -f "$container_name"
    fi
}

strip_requires_db_pre(){
    sed 's/.*Requires[[:space:]].*'"$db//"
}

strip_requires_db_post(){
    sed '
        s/.*Requires[[:space:]]*//;
        s/'"$db"'[[:space:]]*$//
    '
}

# detect version headers and only run if the version corresponds
skip_min_version(){
    local db="$1"
    local version="$2"
    local sql_file="$3"
    local min_version
    local inclusive=""
    if grep -Eiom 1 -- '--[[:space:]]*Requires[[:space:]]+'"$db"'[[:space:]]*N/A' "$sql_file"; then
        timestamp "skipping script '$sql_file' due to N/A version"
        return 0
    fi
    # some versions of sed don't support +, so stick to *
    #                                             Requires PostgreSQL 9.2+
    #                                             Requires 9.2 <= PostgreSQL <= 9.5
    min_version="$(grep -Eiom 1 -- '--[[:space:]]*Requires[[:space:]]+'"$db"'[[:space:]]+(>=?)?[[:space:]]*[[:digit:]]+(\.[[:digit:]]+)?' "$sql_file" | strip_requires_db_pre || :)"
    if [ -z "$min_version" ]; then
        min_version="$(grep -Eiom 1 -- '--[[:space:]]*Requires[[:space:]]+[[:digit:]]+(\.[[:digit:]]+)?[[:space:]]*<=?[[:space:]]*'"$db" "$sql_file" | strip_requires_db_post || :)"
    fi
    if [ -n "$min_version" ] &&
       [ "$version" != latest ]; then
        if [[ "$min_version" =~ \= ]] ||
           ! [[ "$min_version" =~ [\<\>] ]]; then
            inclusive="="
        fi
        min_version="${min_version/>}"
        min_version="${min_version/<}"
        min_version="${min_version/=}"
        min_version="${min_version//[[:space:]]}"
        is_float "$min_version" || die "code error: non-float '$min_version' parsed in skip_min_version()"
        skip_msg="skipping script '$sql_file' due to min required version >$inclusive $min_version"
        is_float "$version" || die "code error: non-float '$version' passed to skip_min_version()"
        if [ -n "$inclusive" ]; then
            if bc_bool "$version < $min_version"; then
                timestamp "$skip_msg"
                return 0
            fi
        else
            if bc_bool "$version <= $min_version"; then
                timestamp "$skip_msg"
                return 0
            fi
        fi
    fi
    return 1
}

# detect version headers and only run if the version corresponds
skip_max_version(){
    local db="$1"
    local version="$2"
    local sql_file="$3"
    local max_version
    local inclusive=""
    if grep -Eiom 1 -- '--[[:space:]]*Requires[[:space:]]+'"$db"'[[:space:]]*N/A' "$sql_file"; then
        timestamp "skipping script '$sql_file' due to N/A version"
        return 0
    fi
    # some versions of sed don't support +, so stick to *
    #                                             Requires PostgreSQL <= 9.1
    max_version="$(grep -Eiom 1 -- '--[[:space:]]*Requires[[:space:]]+.*'"$db"'[[:space:]]+<=?[[:space:]]*[[:digit:]]+(\.[[:digit:]]+)?' "$sql_file" | strip_requires_db_pre || :)"
    if [ -n "$max_version" ]; then
        if [[ "$max_version" =~ = ]]; then
            inclusive="="
        fi
        max_version="${max_version/<}"
        max_version="${max_version/>}"
        max_version="${max_version/=}"
        max_version="${max_version//[[:space:]]}"
        is_float "$max_version" || die "code error: non-float '$max_version' parsed in skip_max_version()"
        skip_msg="skipping script '$sql_file' due to max required version <$inclusive $max_version"
        if [ "$version" = latest ]; then
            timestamp "$skip_msg"
            return 0
        fi
        is_float "$version" || die "code error: non-float '$version' passed to skip_max_version()"
        if [ "$inclusive" = 1 ]; then
            if bc_bool "$version > $max_version"; then
                timestamp "$skip_msg"
                return 0
            fi
        else
            if bc_bool "$version >= $max_version"; then
                timestamp "$skip_msg"
                return 0
            fi
        fi
    fi
    return 1
}