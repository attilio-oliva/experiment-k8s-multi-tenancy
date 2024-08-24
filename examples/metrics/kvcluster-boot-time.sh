#!/bin/bash

# Get all the clusters namespaces
CLUSTERS_NAMESPACES=$(kubectl get clusters -A -o jsonpath='{.items[*].metadata.namespace}')

# Get the boot time of each cluster
for namespace in $CLUSTERS_NAMESPACES; do
    CREATION_TIME=$(kubectl get cluster -n "$namespace" -o jsonpath='{.items[0].metadata.creationTimestamp}')
    CREATION_TIME=$(date -d "$CREATION_TIME" "+%s")

    READY_TIME=$(kubectl get cluster -n "$namespace" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].lastTransitionTime}')
    READY_TIME=$(date -d "$READY_TIME" "+%s")

    BOOT_TIME=$((READY_TIME - CREATION_TIME))

    #  Check if the cluster is a KubevirtCluster
    if kubectl get cluster -n "$namespace" -o jsonpath='{.items[0].spec.infrastructureRef.kind}' | grep -q "KubevirtCluster"; then
        WORKER_MACHINES=$(kubectl get machines -n "$namespace" -o jsonpath='{.items[?(@.metadata.ownerReferences[0].kind!="KubeadmControlPlane")].metadata.name}')

        WORKER_READY_TIME=$(kubectl get machines "$WORKER_MACHINES" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}')
        WORKER_READY_TIME=$(date -d "$WORKER_BOOT_TIME" "+%s")

        MAX_WORKER_READY_TIME=0

        # Iterate over each worker machine to get the longest boot time
        for worker in $WORKER_MACHINES; do
            WORKER_READY_TIME=$(kubectl get machine "$worker" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}')
            WORKER_READY_TIME=$(date -d "$WORKER_READY_TIME" "+%s")

            if [ "$WORKER_READY_TIME" -gt "$MAX_WORKER_READY_TIME" ]; then
                MAX_WORKER_READY_TIME=$WORKER_READY_TIME
            fi
        done
        
        # Calculate the worker boot time relative to the cluster creation time
        WORKER_BOOT_TIME=$((MAX_WORKER_READY_TIME - CREATION_TIME))
        
        # Add the worker boot time to the total boot time
        BOOT_TIME=$((BOOT_TIME + WORKER_BOOT_TIME))
    
        echo "Cluster: $namespace (${BOOT_TIME}s)"
        echo "  - Control Plane: $((READY_TIME - CREATION_TIME))s"
        echo "  - Worker Nodes: $((MAX_WORKER_READY_TIME - CREATION_TIME))s"
    fi
   
done