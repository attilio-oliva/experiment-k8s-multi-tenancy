#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"


NAMESPACE="default"
CLUSTER_KUBECONFIG=$KUBECONFIG

MAX_USERS=1000
NEW_USERS_PER_SECOND=100
RUN_TIME="5m"

# source "https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml"
WEB_SERVICE_MANIFEST="${here}/manifests/webservices.yaml"

KUBECTL="kubectl --kubeconfig=$CLUSTER_KUBECONFIG"

function show_help() {
    cat <<EOF
Usage: ${0##*/} [options]

Options:
  -h  Display this help message
  -k  Path to the kubeconfig file of the cluster
  -n  Namespace where the web service will be created (default: $NAMESPACE)
  -u  Maximum number of users to simulate (default: $MAX_USERS)
  -r  Number of new users to simulate per second (default: $NEW_USERS_PER_SECOND)
  -t  Duration of the test (default: $RUN_TIME)

Note: Remember to use -k option if you are using vCluster for an accurate test from the tenant perspective
EOF
}

function create_web_service() {
    info "Creating the web service"
    $KUBECTL apply -f "$WEB_SERVICE_MANIFEST" -n "$NAMESPACE" 

    info "Waiting for the web service to be ready"
    deployments=("frontend" "cartservice" "checkoutservice" "currencyservice" "emailservice" "paymentservice" "productcatalogservice" "recommendationservice" "shippingservice" "loadgenerator")
    for deployment in "${deployments[@]}"; do
        $KUBECTL wait --for=condition=available deployment/"$deployment" -n "$NAMESPACE" --timeout=5m
    done

    success "Web service created successfully"
}

function stress_test_web_service() {
    info "Starting the stress test"
    # Use locust to stress test the web service
    pod_name=$($KUBECTL get pods -n "$NAMESPACE" -l app="loadgenerator" -o jsonpath="{.items[0].metadata.name}")
    
    # Check if the pod name was retrieved successfully
    if [ -z "$pod_name" ]; then
        error "Failed to get the load generator pod name"
        return 1
    fi
    info "Load generator pod name: $pod_name"
    
    cmd=(
        "locust"
        "--host=http://frontend:80"
        "--headless"
        "-u" "$MAX_USERS"
        "-r" "$NEW_USERS_PER_SECOND"
        "-t" "$RUN_TIME"
    )

    $KUBECTL exec -it "$pod_name" -n "$NAMESPACE" -- "${cmd[@]}"
}


while getopts ":hn:u:r:t:k:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        n)
            NAMESPACE="$OPTARG"
            ;;
        u)
            MAX_USERS="$OPTARG"
            ;;
        r)
            NEW_USERS_PER_SECOND="$OPTARG"
            ;;
        t)
            RUN_TIME="$OPTARG"
            ;;
        k)
            CLUSTER_KUBECONFIG="$OPTARG"
            KUBECTL="$KUBECTL --kubeconfig=$CLUSTER_KUBECONFIG"
            ;;
        \?)
            error "Invalid option: $OPTARG"
            show_help
            exit 1
            ;;
        :)
            error "Option -$OPTARG requires an argument"
            show_help
            exit 1
            ;;
    esac
done

create_web_service
stress_test_web_service
