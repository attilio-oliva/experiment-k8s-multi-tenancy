#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"

# Check if namespace patterns are provided as arguments
if [ "$#" -eq 0 ]; then
    echo "Usage: ${0##*/} <namespace-pattern1> [<namespace-pattern2> ...]"
    exit 1
fi


# Collect namespaces matching the provided patterns
namespaces=()
for pattern in "$@"; do
    matched_namespaces=($(kubectl get namespaces | grep -E "$pattern" | awk '{print $1}'))
    namespaces+=("${matched_namespaces[@]}")
done

info "Checking pod startup times ..."
for namespace in "${namespaces[@]}"; do
    max_time=0
    pod_info=()

    PODS=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}')
    for pod in $PODS; do
        SCHEDULE=$(kubectl -n "$namespace" get pods "$pod" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].lastTransitionTime}')
        READY=$(kubectl -n "$namespace" get pods "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}')
        pod_time=$(( $(date -d "$READY" "+%s") - $(date -d "$SCHEDULE" "+%s") ))
        pod_info+=("  - Pod: $pod (${pod_time}s)")

        if [ $pod_time -gt $max_time ]; then
            max_time=$pod_time
        fi
    done

    echo "Namespace: ${namespace} (${max_time}s)"
    for info in "${pod_info[@]}"; do
        echo "$info"
    done
    echo "--------------------------------------------------------------"
done