#!/bin/bash

set -e

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=/dev/null
source "$here/../common.sh"

# Cluster API
CLUSTERCTL_VERSION="v1.7.4"

# vCluster
INSTALL_VCLUSTER="n"
VCLUSTER_VERSION="v0.20.0"
VCLUSTER_PROVIDER_VERSION="v0.2.0"
VCLUSTER_CAPI_TEMPLATE="manifests/vcluster-capi-template.yaml"

# KubeVirt
INSTALL_KUBEVIRT="n"
KV_VER="1.3.0"
USE_NESTED_VIRTUALIZATION="n"
CAPK_GUEST_K8S_VERSION="v1.26.0"
CRI_PATH="/var/run/containerd/containerd.sock"
NODE_VM_IMAGE_TEMPLATE="quay.io/capk/ubuntu-2004-container-disk:${CAPK_GUEST_K8S_VERSION}"
KV_CAPI_MANIFEST="manifests/kv-capi-template.yaml"


wait_for_namespace_creation() {
    local namespace="$1"
    while [ "$(kubectl get ns $namespace 2>/dev/null)" == "" ]; do
        sleep 2
    done
}

is_clusterctl_installed() {
    if [ -x "$(command -v clusterctl)" ]; then
        return 0
    else
        return 1
    fi
}

install_clusterctl() {
    if is_clusterctl_installed; then
        warning "clusterctl is already installed, skipping installation"
        return
    fi

    info "Installing clusterctl version $CLUSTERCTL_VERSION"

    # Install the clusterctl binary
    curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/$CLUSTERCTL_VERSION/clusterctl-linux-amd64 -o clusterctl
    sudo install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl
    rm clusterctl

    success "clusterctl version $CLUSTERCTL_VERSION installed successfully"

}

install_capi_kubevirt_provider() {
    clusterctl init --infrastructure kubevirt

    # Wait for the CAPI pods to be ready
    info "Waiting for CAPI pods to be ready ..."
    kubectl rollout status deployment/capi-kubeadm-bootstrap-controller-manager -n capi-kubeadm-bootstrap-system --timeout=10m
    kubectl rollout status deployment/capi-kubeadm-control-plane-controller-manager -n capi-kubeadm-control-plane-system --timeout=10m
    kubectl rollout status deployment/capi-controller-manager -n capi-system --timeout=10m
    kubectl rollout status deployment/capk-controller-manager -n capk-system --timeout=10m

    success "CAPI KubeVirt provider installed successfully"
}


install_kubevirt() {
    info "Installing KubeVirt version $KV_VER"

    # deploy required CRDs
    kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KV_VER}/kubevirt-operator.yaml"
    # deploy the KubeVirt custom resource
    kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KV_VER}/kubevirt-cr.yaml"

    info "Waiting for KubeVirt pods to be ready ..."
    kubectl wait -n kubevirt kv kubevirt --for=condition=Available --timeout=10m

    if [ $USE_NESTED_VIRTUALIZATION == "y" ]; then
        kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'
        info "KubeVirt configured to use nested virtualization"
    fi

    success "KubeVirt version $KV_VER installed successfully"
}


is_vcluster_app_installed() {
    if [ -x "$(command -v vcluster)" ]; then
        return 0
    else
        return 1
    fi
}

install_vcluster() {
    if is_vcluster_app_installed; then
        warning "vcluster cli app is already installed, skipping installation"
        return
    fi

    info "Installing vcluster cli app version $VCLUSTER_VERSION"
    
    # Install the vcluster cli tool
    curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/download/$VCLUSTER_VERSION/vcluster-linux-amd64" && sudo install -c -m 0755 vcluster /usr/local/bin && rm -f vcluster

    # Install helm if not already installed (required by vcluster)
    if [ ! -x "$(command -v helm)" ]; then
        warning "Helm not found: installing Helm"
        
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 get_helm.sh
        ./get_helm.sh
        rm get_helm.sh

        info "Helm $(helm version --short) was installed"
    fi

    success "vcluster cli app version $VCLUSTER_VERSION installed successfully"
}

install_vcluster_provider() {
    info "Installing vcluster provider version $VCLUSTER_PROVIDER_VERSION"

    # Latest version of the vcluster provider must be installed
    clusterctl init --infrastructure vcluster:$VCLUSTER_PROVIDER_VERSION

    if [ -n "$HTTP_PROXY" ]; then
        kubectl set env deploy --all -n cluster-api-provider-vcluster-system HTTP_PROXY=$HTTP_PROXY
        info "Applied HTTP_PROXY environment variable to all vcluster provider components"
    fi

    if [ -n "$HTTPS_PROXY" ]; then
        kubectl set env deploy --all -n cluster-api-provider-vcluster-system HTTPS_PROXY=$HTTPS_PROXY
        info "Applied HTTPS_PROXY environment variable to all vcluster provider components"
    fi

    if [ -n "$NO_PROXY" ]; then
        kubectl set env deploy --all -n cluster-api-provider-vcluster-system NO_PROXY=$NO_PROXY
        info "Applied NO_PROXY environment variable to all vcluster provider components"
    fi

    if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ] || [ -n "$NO_PROXY" ]; then
        warning "Remember to set add to the NO_PROXY environment variable for the hostnames of your clusters
        For example, a cluster created in a namespace 'foo', add it to the NO_PROXY environment variable:
          NO_PROXY=\$NO_PROXY,.foo
          kubectl set env deploy --all -n cluster-api-provider-vcluster-system NO_PROXY=\$NO_PROXY"
    fi

    success "vcluster provider version $VCLUSTER_PROVIDER_VERSION installed successfully"
}

install_kata_container() {
    info "Installing Kata Containers using kata-deploy"

    kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml
    kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy.yaml
    kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-deploy pod

    kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/runtimeclasses/kata-runtimeClasses.yaml

    success "Kata Containers installed successfully"
}

create_kv_cluster_example() {
    if [ -z "$KV_CAPI_MANIFEST" ]; then
        warning "Manifest not found: using the default CAPI Kubevirt cluster template"
        
        clusterctl generate cluster capi-quickstart \
      --infrastructure="kubevirt" \
      --flavor lb \
      --kubernetes-version ${CAPK_GUEST_K8S_VERSION} \
      --control-plane-machine-count=1 \
      --worker-machine-count=1 \
      > capi-quickstart.yaml

      $KV_CAPI_MANIFEST="capi-quickstart.yaml"
    else
        info "Manifest found: using the provided CAPI Kubevirt cluster template"
    fi

    kubectl apply -f $KV_CAPI_MANIFEST
    success "Cluster created successfully"

    echo "To get the updated status of the cluster, run the following command:"
    echo "watch --color clusterctl describe cluster capi-quickstart -c"
}

create_vcluster_example() {
    export CLUSTER_NAME=test-vcluster
    export CLUSTER_NAMESPACE=my-vcluster-qemu
    export KUBERNETES_VERSION=1.29.7
    #export VCLUSTER_YAML=""
    # Uncomment if you want to use vcluster values
    export VCLUSTER_YAML=$(cat vcluster/values.yaml | awk '{printf "%s\\n", $0}')

    kubectl create namespace ${CLUSTER_NAMESPACE}

    clusterctl generate cluster ${CLUSTER_NAME} \
    --infrastructure vcluster \
    --kubernetes-version ${KUBERNETES_VERSION} \
    --target-namespace ${CLUSTER_NAMESPACE} | kubectl apply -f -
}



# If no arguments are provided, install both KubeVirt and vCluster
if [ $# -eq 0 ]; then
    INSTALL_KUBEVIRT="y"
    INSTALL_VCLUSTER="y"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--kubevirt)
            INSTALL_KUBEVIRT="y"
            shift
            ;;
        -v|--vcluster)
            INSTALL_VCLUSTER="y"
            shift
            ;;
        *)
            echo "Usage: setup.sh [-k|--kubevirt to install KubeVirt] [-v|--vcluster to install vCluster]"
            echo "If no arguments are provided, both KubeVirt and vCluster will be installed"
            exit 1
            ;;
    esac
done

install_clusterctl

if [ $INSTALL_KUBEVIRT == "y" ]; then
    install_kubevirt
    install_capi_kubevirt_provider
fi

if [ $INSTALL_VCLUSTER == "y" ]; then
    install_vcluster
    install_vcluster_provider
fi