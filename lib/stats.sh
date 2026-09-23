#!/usr/bin/env bash

write_duration_statistics() {
    local durations_file=$1
    shift
    local count
    local percentile
    local index
    local duration

    count=$(wc -l < "$durations_file" | tr -d ' ')
    if ((count == 0)); then
        printf 'No successful request durations available.\n'
        return
    fi

    printf 'Average request duration: %.2f ms\n' "$(awk '{ total += $1 } END { print total / NR }' "$durations_file")"
    for percentile in "$@"; do
        index=$(((percentile * count + 99) / 100))
        duration=$(LC_ALL=C sort -n "$durations_file" | sed -n "${index}p")
        printf 'P%s request duration: %.2f ms\n' "$percentile" "$duration"
    done
}