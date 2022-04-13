#!/bin/bash

script_location="$(dirname "${BASH_SOURCE[0]}")"
emojivoto_instances=5

function grace() {
    grace=3
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
            echo "wait: $grace s"
            grace=$(($grace-1))
            continue
        fi
        
        break
    done
}
# --

function install_emojivoto() {
    local mesh="$1"

    echo "Installing emojivoto."

    for num in $(seq 0 1 ${emojivoto_instances}); do
        { 
            kubectl create namespace emojivoto-$num
            helm install emojivoto-$num --namespace emojivoto-$num ./configs/emojivoto/
         } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 3
}
# --

function restart_emojivoto_pods() {

    for num in $(seq 0 1 ${emojivoto_instances}); do
        local ns="emojivoto-$num"
        echo "Restarting pods in $ns"
        {  local pods="$(kubectl get -n "$ns" pods | grep -vE '^NAME' | awk '{print $1}')"
            kubectl delete -n "$ns" pods $pods --wait; } &
    done

    wait

    grace "kubectl get pods --all-namespaces | grep emojivoto | grep -v Running" 3
}
# --

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

function run() {
    echo "   Running '$@'"
    $@
}
# --

function install_benchmark() {
    local mesh="$1"
    local rps="$2"

    local duration=300 # 5 mins
    local init_delay=10

    local app_count="$(kubectl get namespaces | grep emojivoto | wc -l | xargs)"

    echo -e "\n\nRunning $mesh benchmark"
    kubectl create ns benchmark
    echo -e "\n"
    echo "app_count: ${app_count}, rps=${rps}, duration=${duration}, init_delay=${init_delay}"
    helm install benchmark --namespace benchmark \
        --set wrk2.app.count="$app_count" \
        --set wrk2.RPS="$rps" \
        --set wrk2.duration=$duration \
        --set wrk2.initDelay=$init_delay \
        --set wrk2.connections=128 \
        ./configs/benchmark/
}
# --

function run_bench() {
    local mesh="$1"
    local rps="$2"

    install_benchmark "$mesh" "$rps"
    grace "kubectl get pods -n benchmark | grep wrk2-prometheus | grep -v Running" 3

    echo "Benchmark started."

    while kubectl get jobs -n benchmark \
            | grep wrk2-prometheus \
            | grep -qv 1/1; do
        kubectl logs \
                --tail 1 -n benchmark  jobs/wrk2-prometheus -c wrk2-prometheus
        sleep 3
    done

    echo "Benchmark concluded. Updating summary metrics."
    helm install --create-namespace --namespace metrics-merger metrics-merger ./configs/metrics-merger/
    sleep 5
    while kubectl get jobs -n metrics-merger \
            | grep wrk2-metrics-merger \
            | grep  -v "1/1"; do
        sleep 1
    done

    kubectl logs -n metrics-merger jobs/wrk2-metrics-merger

    echo "Cleaning up."
    helm uninstall benchmark --namespace benchmark
    kubectl delete ns benchmark --wait
    helm uninstall --namespace metrics-merger metrics-merger
    kubectl delete ns metrics-merger --wait
}
# --

# --
function run_benchmarks() {
    #for rps in 500 600; do  #  1000 1500 2000 2500 3000 3500 4000 4500 5000 5500; do
    rps=500
    for repeat in 1 2 3 4 5; do

        echo -e "\n\n########## Run #$repeat w/ $rps RPS"

        echo -e "\n+++ bare metal benchmark +++"
        install_emojivoto bare-metal
        run_bench bare-metal $rps
        delete_emojivoto
    done
    #done
}
# --

run_benchmarks $@
