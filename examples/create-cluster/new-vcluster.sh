#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"


CLUSTER_NAMESPACE="my-vcluster"
CLUSTER_NAME="vcluster"
KUBERNETES_VERSION=1.29.7


VCLUSTER_CAPI_MANIFEST=""
VCLUSTER_VALUES_FILE=""
ALTERNATIVE_HOSTNAMES=""
USE_LOCAL_IPS_AS_ALTERNATIVE_HOSTNAMES="n"

OUT_MANIFEST_DIR="${here}/manifests/vclusters"


function show_help() {
    cat <<EOF
Usage: ${0##*/} [options] [CLUSTER_NAME]

Options:
  -h  Display this help message
  -f  Path to the CAPI vCluster manifest (all other options will be ignored)
  -n  Namespace where the cluster will be created (default: $CLUSTER_NAMESPACE)
  -v  Path to the vCluster YAML Helm values file

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

function create_vcluster() {
    info "Creating a new vCluster cluster"

    # if the user provided a valid manifest, use it
    if [ -n "$VCLUSTER_CAPI_MANIFEST" ] && [ -f "$VCLUSTER_CAPI_MANIFEST" ]; then
        info "Using the provided CAPI vCluster manifest"
    else 
        VALUES_NAME="default"
        VCLUSTER_YAML=""

        if [ -n "$VCLUSTER_VALUES_FILE" ] && [ -f "$VCLUSTER_VALUES_FILE" ]; then
            local alternative_hostnames="${ALTERNATIVE_HOSTNAMES:-}"

            if [ "$USE_LOCAL_IPS_AS_ALTERNATIVE_HOSTNAMES" == "y" ]; then
                # Get the internal IPs of the nodes and separate them with commas followed by a space
                local_ips=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | sed 's/ /, /g')
                
                if [ -n "$alternative_hostnames" ]; then
                    alternative_hostnames="${alternative_hostnames}, ${local_ips}"
                else
                    alternative_hostnames="${local_ips}"
                fi
            fi
            
            if [ -n "$alternative_hostnames" ]; then
                VCLUSTER_YAML=$(ALTERNATIVE_HOSTNAMES="$alternative_hostnames" envsubst "\${ALTERNATIVE_HOSTNAMES}" < "$VCLUSTER_VALUES_FILE")
            else
                VCLUSTER_YAML=$(cat "$VCLUSTER_VALUES_FILE")
            fi

            # Ensure VCLUSTER_YAML is properly formatted
            VCLUSTER_YAML=$(awk '{printf "%s\\n", $0}' <<< "$VCLUSTER_YAML")
        fi
 
        export VCLUSTER_YAML
        
        # Get the file name
        VALUES_NAME=${VCLUSTER_VALUES_FILE##*/}
        # Remove the file extension
        VALUES_NAME=${VALUES_NAME%.*}

        MANIFEST_NAME="${CLUSTER_NAMESPACE}-${CLUSTER_NAME}-${VALUES_NAME}.yaml"
        VCLUSTER_CAPI_MANIFEST="${OUT_MANIFEST_DIR}/${MANIFEST_NAME}"
        
        mkdir -p "$OUT_MANIFEST_DIR"

        # Create the namespace if it doesn't exist
        kubectl create namespace "${CLUSTER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

        clusterctl generate cluster "${CLUSTER_NAME}" \
        --infrastructure vcluster \
        --kubernetes-version ${KUBERNETES_VERSION} \
        --target-namespace "${CLUSTER_NAMESPACE}" \
        >  "${VCLUSTER_CAPI_MANIFEST}"

        if [ ! -f "$VCLUSTER_CAPI_MANIFEST" ]; then
            error "Generated manifest not found in path $VCLUSTER_CAPI_MANIFEST"
            exit 1
        fi
    fi

    if [ -n "$HTTP_PROXY" ]; then
        PROVIDER_NO_PROXY=$(kubectl get deploy -n cluster-api-provider-vcluster-system -o jsonpath='{.items[0].spec.template.spec.containers[0].env[?(@.name=="NO_PROXY")].value}')
        
        # check if NO_PROXY do not contains the new entry already
        # Otherwise, cluster-api-provider-vcluster-system will not be able to communicate with the cluster
        if [[ ! $PROVIDER_NO_PROXY == *".$CLUSTER_NAMESPACE"* ]]; then
            
            PROVIDER_NO_PROXY="$PROVIDER_NO_PROXY,.$CLUSTER_NAMESPACE"
            kubectl set env deploy --all -n cluster-api-provider-vcluster-system NO_PROXY="$PROVIDER_NO_PROXY"
            
            info "Added $CLUSTER_NAMESPACE to the NO_PROXY list of the vCluster provider"
            sleep 3
        fi
        
    fi

    kubectl apply -f "$VCLUSTER_CAPI_MANIFEST"
    success "Cluster created successfully"

    info "To get the updated status of the cluster, run the following command:
            watch --color clusterctl describe cluster ${CLUSTER_NAME} -n ${CLUSTER_NAMESPACE} -c"
}

if ! is_clusterctl_installed; then
    error "clusterctl is not installed. Please install it first"
    exit 1
fi


while getopts "n:v:f:a:lh" opt; do
    case "$opt" in
    h)  show_help
        exit 0
        ;;
    f)  VCLUSTER_CAPI_MANIFEST=$OPTARG
        ;;
    n)  CLUSTER_NAMESPACE=$OPTARG
        ;;
    v)  VCLUSTER_VALUES_FILE=$OPTARG
        ;;
    a)  ALTERNATIVE_HOSTNAMES=$OPTARG
        ;;
    l)  USE_LOCAL_IPS_AS_ALTERNATIVE_HOSTNAMES="y"
        ;;
    \?) error "Invalid option: $opt"
        show_help
        exit 1
        ;;
    esac
done

# Remove the parsed options from the positional parameters
shift $((OPTIND-1))

# Check if the user provided a cluster name as an argument at the end of the command
if [ $# -gt 0 ]; then
    CLUSTER_NAME=$1
fi

create_vcluster 