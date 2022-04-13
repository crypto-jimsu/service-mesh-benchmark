# Kinvolk service mesh benchmark suite

This is v2.0 release of our benchmark automation suite.

Please refer to the [1.0 release](tree/release-1.0) for automation discussed in our [2019 blog post](https://kinvolk.io/blog/2019/05/kubernetes-service-mesh-benchmarking/).

# Customize for my project
```
Before you start running, make sure the following things be instlled already:
- helm https://helm.sh/docs/intro/install/
```
### Verify helm
$ helm version
version.BuildInfo{Version:"v3.8.1", GitCommit:"5cb9af4b1b271d11d7a97a71df3ac337dd94ad37", GitTreeState:"clean", GoVersion:"go1.17.8"}
```
- istioctl version 1.12.5 https://istio.io/latest/docs/setup/getting-started/#download
```
### Verfiy istioctl install
$ istioctl version
no running Istio pods in "istio-system"
1.12.5
```
- linkerd version stable-2.11.1 https://linkerd.io/2.11/getting-started/
```
### Verfiy linkerd install
$ linkerd version
Client version: stable-2.11.1
Server version: unavailable
```

- Prometheus & Grafana
```
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade -i prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2",server.persistentVolume.storageClass="gp2"


cat << EoF > ~/Desktop/grafana.yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true
EoF

helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
    --namespace monitoring \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='EKS!sAWSome' \   # <- Just for tesing !!!!!!!! You can change it for another value
    --values ~/Desktop/grafana.yaml

### Verfiy Prometheus & Grafana 
$ kubectl get pod -n monitoring
NAME                                             READY   STATUS    RESTARTS   AGE
grafana-85966c76d7-g99hn                         1/1     Running   0          8h
prometheus-alertmanager-565889745c-wqtz2         2/2     Running   0          8h
prometheus-kube-state-metrics-7c6ffc7686-dkr4n   1/1     Running   0          8h
prometheus-node-exporter-c95nb                   1/1     Running   0          117m
prometheus-node-exporter-gmfhb                   1/1     Running   0          117m
prometheus-node-exporter-m5cxk                   1/1     Running   0          117m
prometheus-node-exporter-mvqlg                   1/1     Running   0          117m
prometheus-node-exporter-z2sj7                   1/1     Running   0          118m
prometheus-pushgateway-5f9b4489f-7lx8f           1/1     Running   0          8h
prometheus-server-5bd98fd4d4-fpn6b               2/2     Running   0          8h
```

- Worker nodes are labeled with `role: workload` and `role: benchmark`
```
### Verify worker node
$ kubectl get node -l role=workload
NAME                              STATUS   ROLES    AGE    VERSION
ip-192-168-101-168.ec2.internal   Ready    <none>   121m   v1.19.15-eks-9c63c4
ip-192-168-116-144.ec2.internal   Ready    <none>   121m   v1.19.15-eks-9c63c4
ip-192-168-66-33.ec2.internal     Ready    <none>   121m   v1.19.15-eks-9c63c4
ip-192-168-81-153.ec2.internal    Ready    <none>   121m   v1.19.15-eks-9c63c4

$ kubectl get node -l role=benchmark
NAME                              STATUS   ROLES    AGE    VERSION
ip-192-168-114-150.ec2.internal   Ready    <none>   121m   v1.19.15-eks-9c63c4


- Set up grafana dashboard, pleas follow https://github.com/crypto-jimsu/service-mesh-benchmark#upload-grafana-dashboard
```


# Content

The suite includes:
- orchestrator [tooling](orchestrator) and [Helm charts](configs/orchestrator)
    for deploying benchmark clusters from an orchestrator cluster
    - metrics of all benchmark clusters will be scraped and made available in
      the orchestrator cluster
- a stand-alone benchmark cluster [configuration](configs/equinix-metal-cluster.lokocfg)
    for use with [Lokomotive](https://github.com/kinvolk/lokomotive/releases/)
- helm charts for deploying [Emojivoto](configs/emojivoto)
    to provide application endpoints to run benchmarks against
- helm charts for deploying a [wrk2 benchmark job](configs/benchmark) as well
  as a job to create
    [summary metrics of multiple benchmark runs](configs/metrics-merger)
- Grafana [dashboards](dashboards/) to view benchmark metrics

## Run a benchmark

Prerequisites (This should not worries, if you make sure the above `Customize for my project` is done):
- cluster is set up
- push gateway is installed
- grafana dashboards are uploaded to Grafana
- applications are installed

1. Start the benchmark:
   ```shell
   $ helm install --create-namespace benchmark --namespace benchmark configs/benchmark
   ```
   This will start a 120s, 3000RPS benchmark against 10 emojivoto app
   instances, with 96 threads / simultaneous connections.
   See the helm chart [values](configs/benchmark/values.yaml) for all
   parameters, and use helm command line parameters for different values (eg.
   `--set wrk2.RPS="500"` to change target RPS).
2. Refer to the "wrk2 cockpit" grafana dashboard for live metrics
3. After the run concluded, run the "metrics-merger" job to update summary
   metrics:
   ```shell
   $ helm install --create-namespace --namespace metrics-merger \
                                   metrics-merger configs/metrics-merger/
   ```
   This will update the "wrk2 summary" dashboard.

## Run a benchmark suite

The benchmark suite script will install applications and service meshes, and
run several benchmarks in a loop.

Use the supplied `scripts/run_benchmarks.sh` to run a full benchmark suite:
5 runs of 10 minutes each for 500-5000 RPS, in 500 RPS increases, with 128 threads,
for "bare metal", linkerd, and istio service meshes, against 60 emojivoto
instances.

# Creating prerequisites
## Set up a cluster
We use EKS cluster for testing

## Deploy prometheus push gateway

The benchmark load generator will push intermediate run-time metrics as well
as final latency metrics to a prometheus push gateway.
A push gateway is currently not bundled with Lokomotive's prometheus
component. Deploy by issuing
```
$ helm install pushgateway --namespace monitoring configs/pushgateway
```

## Deploy demo apps

Demo apps will be used to run the benchmarks against. We'll use [Linkerd's
emojivoto](https://github.com/BuoyantIO/emojivoto).

We will deploy multiple instances of each app to emulate many applications in a
cluster. For the default set-up, which includes 4 application nodes, we
recommend deploying 30 "bookinfo" instances, and 40 "emojivoto" instances:

```shell
$ cd configs
$ for i in $(seq 10) ; do \
      helm install --create-namespace emojivoto-$i \ --namespace emojivoto-$i \
                configs/emojivoto \
  done
```

### Upload Grafana dashboard
1. Forward the Grafana service port from the cluster
   ```
   $ kubectl -n monitoring port-forward svc/prometheus-operator-grafana 3000:80 &
   ```
2. Log in to [Grafana](http://localhost:3000/) and create an API key we'll use to upload the dashboard
3. Upload the dashboard:
   ```
   $ cd dashboard
   dashboard $ ./upload_dashboard.sh "[API KEY]" grafana-wrk2-cockpit.json localhost:3000
   ```

