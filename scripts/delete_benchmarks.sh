#!/bin/bash
emojivoto_instances=5

function grace() {
    grace=10
    [ -n "$2" ] && grace="$2"

    while true; do
        eval $1
        if [ $? -eq 0 ]; then
            sleep 1
            grace=10
            continue
        fi

        if [ $grace -gt 0 ]; then
            sleep 1
            echo "grace period: $grace"
            grace=$(($grace-1))
            continue
        fi
        
        break
    done
}

function delete_emojivoto() {
    echo "Deleting emojivoto."

    for i in $(seq 0 1 ${emojivoto_instances}); do
        { helm uninstall emojivoto-$i --namespace emojivoto-$i;
          kubectl delete namespace emojivoto-$i --wait; } &
    done

    wait

    grace "kubectl get namespaces | grep emojivoto"
}
# --

function delete_istio() {
    echo "Start delete Istio"
    yes | istioctl x uninstall --purge
    echo "Deleted Istio"
}
# --

function delete_linkerd() {
    echo "Start delete linkerd"
    linkerd viz uninstall | kubectl delete -f -
    linkerd uninstall | kubectl delete -f -

    grace "kubectl get namespaces | grep linkerd" 1
    kubectl delete namespace linkerd  --now --timeout=30s
    echo "Deleted linkerd"
    sleep 5
}

# --
function delete_benchmarks() {

    delete_emojivoto

    echo "Removing linkerd"
    delete_linkerd
    
    echo "Removing lstio"
    delete_istio

    echo "Cleaning up."
    helm uninstall benchmark --namespace benchmark
    kubectl delete ns benchmark --wait
    helm uninstall --namespace metrics-merger metrics-merger
    kubectl delete ns metrics-merger --wait
}
# --

if [ "$(basename $0)" = "delete_benchmarks.sh" ] ; then
    delete_benchmarks $@
fi
