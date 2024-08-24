#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"


VCLUSTER_NODEPORT_MANIFEST="${here}/manifests/vcluster-nodeport.yaml"
OUT_KUBECONFIG_DIR="${here}/kubeconfigs"

USE_CLUSTERCTL="n"
USE_VCLUSTER="n"
GET_ALL_CLUSTERS="n"

CLUSTER_NAMESPACE="default"
CLUSTER_NAME=""


mkdir -p "$OUT_KUBECONFIG_DIR"

function show_help() {
    cat <<EOF
Usage: $0 [OPTIONS] [CLUSTER_NAME]

Options:
  -c, --clusterctl    Get kubeconfigs using Cluster API utility (clusterctl)
  -v, --vcluster      Get kubeconfigs using vCluster utility (vcluster) and expose with NodePort service
  -a, --all           Get kubeconfigs for all clusters (vCluster and Cluster API)
  -n, --namespace     Namespace where the clusters are located
  -h, --help          Display this help message

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

function is_vcluster_app_installed() {
    if [ -x "$(command -v vcluster)" ]; then
        return 0
    else
        return 1
    fi
}


function get_clusterctl_kubeconfigs() {
    if ! is_clusterctl_installed; then
        error "clusterctl is not installed, please install it first"
    fi

    while read -r namespace cluster; do
        info "Getting kubeconfig for cluster $cluster in namespace $namespace"
        kubeconfig=$(clusterctl get kubeconfig "$cluster" -n "$namespace") || error "Failed to get kubeconfig for cluster $cluster"
        echo "$kubeconfig" > "${OUT_KUBECONFIG_DIR}/${namespace}-${cluster}.yaml"
    done <<< "$cluster_list"
}

function get_vcluster_kubeconfigs() {
    if ! is_vcluster_app_installed; then
        error "vCluster is not installed, please install it first"
    fi

    while read -r namespace cluster; do
        info "Processing vCluster $cluster in namespace $namespace"
        info "Exposing cluster with NodePort service..."
        expose_vcluster_svc "$cluster" "$namespace"
        
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        NODEPORT_PORT=$(kubectl get svc -n "$namespace" -o jsonpath='{.items[?(@.spec.type=="NodePort")].spec.ports[0].nodePort}')
        
        info "Getting kubeconfig..."
        kubeconfig=$(vcluster connect "$cluster" -n "$namespace" --print --server=https://"${NODE_IP}":"${NODEPORT_PORT}") || error "Failed to get kubeconfig for vCluster $cluster"
        
        if [ -n "$kubeconfig" ]; then
            echo "$kubeconfig" > "${OUT_KUBECONFIG_DIR}/${namespace}-${cluster}.yaml"
            success "Accessible with nodeport at $NODE_IP:$NODEPORT_PORT"
        fi

    done <<< "$vcluster_list"
}

function expose_vcluster_svc() {
    local cluster="$1"
    local namespace="$2"

    NODEPORT_MANIFEST=$(CLUSTER_NAME=$cluster NAMESPACE=$namespace envsubst '$CLUSTER_NAME,$NAMESPACE' < "$VCLUSTER_NODEPORT_MANIFEST")
   
    echo "$NODEPORT_MANIFEST" | kubectl apply -f - -n "$namespace" || error "Failed to expose the vCluster service for cluster $cluster"
}

if [ $# -eq 0 ]; then
    USE_CLUSTERCTL="y"
    USE_VCLUSTER="n"
    GET_ALL_CLUSTERS="y"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--clusterctl)
            USE_CLUSTERCTL="y"
            shift
            ;;
        -v|--vcluster)
            USE_VCLUSTER="y"
            shift
            ;;
        -a|--all)
            GET_ALL_CLUSTERS="y"
            shift
            ;;
        -n|--namespace)
            CLUSTER_NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$CLUSTER_NAME" ]]; then
                CLUSTER_NAME="$1"
                shift
            else
                show_help
                exit 1
            fi
            ;;
    esac
done



if [ "$GET_ALL_CLUSTERS" == "y" ]; then
    cluster_list=$(kubectl get clusters -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}')
    vcluster_list=$(kubectl get vclusters -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}')
else 
    if [ -n "$CLUSTER_NAME" ]; then

        cluster_list=$(kubectl get clusters -n "$CLUSTER_NAMESPACE" "$CLUSTER_NAME" -o jsonpath='{.metadata.namespace} {.metadata.name}')
        vcluster_list=$(kubectl get vclusters -n "$CLUSTER_NAMESPACE" "$CLUSTER_NAME" -o jsonpath='{.metadata.namespace} {.metadata.name}')
     else 
        cluster_list=$(kubectl get clusters -n "$CLUSTER_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}')
        vcluster_list=$(kubectl get vclusters -n "$CLUSTER_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name}{"\n"}{end}')
    fi
fi

if [ "$USE_CLUSTERCTL" == "y" ]; then
    get_clusterctl_kubeconfigs
fi

if [ "$USE_VCLUSTER" == "y" ]; then
    get_vcluster_kubeconfigs
fi


success "Kubeconfigs saved in ${OUT_KUBECONFIG_DIR}"