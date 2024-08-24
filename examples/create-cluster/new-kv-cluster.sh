#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"


CLUSTER_NAMESPACE="capi-quickstart"
CLUSTER_NAME="capi-quickstart"

export CAPK_GUEST_K8S_VERSION="v1.26.0"
export CRI_PATH="/var/run/containerd/containerd.sock"
export NODE_VM_IMAGE_TEMPLATE="quay.io/capk/ubuntu-2004-container-disk:${CAPK_GUEST_K8S_VERSION}"
export CONTROL_PLANE_MACHINE_COUNT=1
export WORKER_MACHINE_COUNT=1

KV_CAPI_TEMPLATE="${here}/manifests/kv-capi-template.yaml"
KV_CAPI_MANIFEST=""

OUT_MANIFEST_DIR="${here}/manifests/kv_clusters"


function show_help() {
    cat <<EOF
Usage: ${0##*/} [options] [CLUSTER_NAME]

Options:
  -h  Display this help message
  -f  Path to the CAPI Kubevirt cluster manifest (all other options will be ignored)
  -t  Path to the CAPI Kubevirt cluster template
  -n  Namespace where the cluster will be created (default: $CLUSTER_NAMESPACE)
  -c  Number of control plane machines (default: $CONTROL_PLANE_MACHINE_COUNT)
  -w  Number of worker machines (default: $WORKER_MACHINE_COUNT)

Arguments:
  CLUSTER_NAME  Name of the cluster to be created (default: $CLUSTER_NAME)
EOF
}


function is_clusterctl_installed() {
    if [ -x "$(command -v clusterctl)" ]; then
        return 0
    else
        return 1
    fi
}

function create_kv_cluster() {
    info "Creating a new Kubevirt cluster"

    # if the user provided a valid manifest, use it
    if [ -n "$KV_CAPI_MANIFEST" ] && [ -f "$KV_CAPI_MANIFEST" ]; then
        info "Using the provided CAPI Kubevirt cluster manifest"
    else 
        MANIFERS_NAME="${CLUSTER_NAME}-${CLUSTER_NAME}-c${CONTROL_PLANE_MACHINE_COUNT}-w${WORKER_MACHINE_COUNT}.yaml"
        KV_CAPI_MANIFEST="${OUT_MANIFEST_DIR}/${MANIFERS_NAME}"

        mkdir -p $OUT_MANIFEST_DIR

         # Create the namespace if it doesn't exist
        kubectl create namespace ${CLUSTER_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

        if [ -z "$KV_CAPI_TEMPLATE" ]; then
            warning "Template not provided: using the default CAPI Kubevirt cluster template"
            
            clusterctl generate cluster ${CLUSTER_NAME} \
              --target-namespace=${CLUSTER_NAMESPACE} \
              --infrastructure="kubevirt" \
              --flavor lb \
              --kubernetes-version ${CAPK_GUEST_K8S_VERSION} \
              --control-plane-machine-count=${CONTROL_PLANE_MACHINE_COUNT} \
              --worker-machine-count=${WORKER_MACHINE_COUNT} \
              >  ${KV_CAPI_MANIFEST}    
        else
            clusterctl generate cluster ${CLUSTER_NAME} \
              --target-namespace=${CLUSTER_NAMESPACE} \
              --from ${KV_CAPI_TEMPLATE} \
              --kubernetes-version ${CAPK_GUEST_K8S_VERSION} \
              --control-plane-machine-count=${CONTROL_PLANE_MACHINE_COUNT} \
              --worker-machine-count=${WORKER_MACHINE_COUNT} \
              >  ${KV_CAPI_MANIFEST}
        fi

        if [ ! -f "$KV_CAPI_MANIFEST" ]; then
            error "Generated manifest not found in path $KV_CAPI_MANIFEST"
            exit 1
        fi
    fi

    kubectl apply -f $KV_CAPI_MANIFEST
    success "Cluster created successfully"

    info "To get the updated status of the cluster, run the following command:
            watch --color clusterctl describe cluster ${CLUSTER_NAME} -n ${CLUSTER_NAMESPACE} -c"
}

if ! is_clusterctl_installed; then
    error "clusterctl is not installed. Please install it first"
    exit 1
fi


# if no arguments are provided, show the help message
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi


while getopts "f:t:n:c:w:h" opt; do
    case "$opt" in
    h)  show_help
        exit 0
        ;;
    f)  KV_CAPI_MANIFEST=$OPTARG
        ;;
    t)  KV_CAPI_TEMPLATE=$OPTARG
        ;;
    n)  CLUSTER_NAMESPACE=$OPTARG
        ;;
    c)  CONTROL_PLANE_MACHINE_COUNT=$OPTARG  
        ;;
    w)  WORKER_MACHINE_COUNT=$OPTARG
        ;;
    *)
        show_help
        exit 1
        ;;
    esac
done

# Remove the parsed options from the positional parameters
shift $((OPTIND-1))

# Check if the user provided a cluster name as an argument, at the end of the command
if [ $# -gt 0 ]; then
    CLUSTER_NAME=$1
fi

create_kv_cluster 