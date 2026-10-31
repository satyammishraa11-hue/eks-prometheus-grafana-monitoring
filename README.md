# EKS Monitoring with Prometheus, Grafana and Alertmanager

A hands-on AWS DevOps/SRE lab that provisions Amazon EKS using **Terraform**, installs the **kube-prometheus-stack** using **Helm**, monitors Kubernetes CPU and memory workloads using **Prometheus and Grafana**, and evaluates threshold-based alerts using **PrometheusRule** and **Alertmanager**.

## Architecture

```text
Terraform -> AWS VPC (existing default VPC) -> Amazon EKS
                                             |-- 2 managed worker nodes
                                             |-- metrics-server
                                             |-- namespace: monitoring
                                             |    |-- Prometheus + Operator
                                             |    |-- Grafana
                                             |    |-- Alertmanager
                                             |    |-- node-exporter / kube-state-metrics
                                             |-- namespace: monitoring-lab
                                                  |-- cpu-stress-app
                                                  |-- memory-stress-app

Container / node metrics -> Prometheus -> Grafana dashboards
                                      -> PrometheusRule -> Alertmanager
```

Grafana **queries** Prometheus; Alertmanager receives firing alerts from Prometheus. These are separate paths, not a serial Grafana-to-Alertmanager pipeline.

## Tools

- AWS EKS, EC2, IAM, VPC
- Terraform, AWS CLI, kubectl, Helm
- Kubernetes Deployments and Namespaces
- Prometheus, PromQL, Prometheus Operator, Alertmanager
- Grafana dashboards

## Repository layout

```text
.
├── README.md
├── .gitignore
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars.example
├── nodeport-values.yaml
├── monitoring-lab/
│   ├── cpu-stress.yaml
│   ├── memory-stress.yaml
│   └── lab-alerts.yaml
└── grafana/
    └── eks-monitoring-dashboard.json
```

The Grafana dashboard was exported after being built manually in the web UI.

## Prerequisites

Install/configure Terraform, AWS CLI, `kubectl`, and Helm. Configure an AWS identity with the required permissions. This Terraform configuration reuses the account's **default VPC** in `ap-south-1` and requires at least two suitable subnets in different availability zones.

> **Costs:** Amazon EKS, EC2, EBS, public IPv4 addresses, and other AWS services can generate charges. Check eligibility and quotas for the selected EC2 type. Run cleanup after the lab.

## 1. Provision Amazon EKS with Terraform

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: especially admin_cidr = "YOUR_PUBLIC_IPV4/32"
# Choose an available node_instance_type and review node sizing.
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Update local Kubernetes credentials:

```bash
aws eks update-kubeconfig --region ap-south-1 --name monitoring-eks-cluster
kubectl get nodes
kubectl get pods -A
kubectl top nodes
```

The lab used two EKS managed worker nodes and the Metrics Server add-on. The exact instance type is controlled by the Terraform variables.

## 2. Install the monitoring stack using Helm

```bash
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --wait --timeout 10m
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

For private local access (recommended), use separate terminals:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Grafana: `http://localhost:3000` · Prometheus: `http://localhost:9090` · Alertmanager: `http://localhost:9093`.

The lab also explored `nodeport-values.yaml` to configure NodePort Services. **Do not leave monitoring interfaces publicly exposed:** if testing NodePort, restrict ingress to your IP and remove access afterward. Port-forwarding or authenticated HTTPS behind private access is safer.

## 3. Deploy CPU and memory test workloads

```bash
kubectl create namespace monitoring-lab
kubectl apply -f monitoring-lab/cpu-stress.yaml
kubectl apply -f monitoring-lab/memory-stress.yaml
kubectl get pods -n monitoring-lab -o wide
kubectl top pods -n monitoring-lab
```

In this practical, the CPU workload reached approximately **500m CPU** and the memory workload approximately **513 MiB**. Actual results vary by node and workload.

## 4. PromQL queries

**CPU usage by Pod (cores):**

```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="monitoring-lab",container!="",container!="POD"}[5m]))
```

**Memory working set by Pod (bytes):**

```promql
sum by (pod) (container_memory_working_set_bytes{namespace="monitoring-lab",container!="",container!="POD"})
```

**CPU usage as percent of container limit:**

```promql
100 * sum by (namespace,pod,container) (rate(container_cpu_usage_seconds_total{namespace="monitoring-lab",container!="",container!="POD"}[5m])) / sum by (namespace,pod,container) (kube_pod_container_resource_limits{namespace="monitoring-lab",resource="cpu",unit="core"})
```

**Memory usage as percent of container limit:**

```promql
100 * sum by (namespace,pod,container) (container_memory_working_set_bytes{namespace="monitoring-lab",container!="",container!="POD"}) / sum by (namespace,pod,container) (kube_pod_container_resource_limits{namespace="monitoring-lab",resource="memory",unit="byte"})
```

## 5. Grafana dashboard

Four dashboard panels were configured:

1. CPU usage by Pod (time series)
2. Memory usage by Pod (time series, Bytes IEC)
3. CPU usage / limit (gauge, %)
4. Memory usage / limit (gauge, %)

Import `grafana/eks-monitoring-dashboard.json` using **Grafana → Dashboards → New → Import**, and select the Prometheus data source. This file is an export of the manually built dashboard, rather than a running Grafana database backup.

### Observed lab results

- CPU test workload: ~500m CPU, with gauge readings up to ~96.8% of its configured limit.
- Memory test workload: ~513 MiB, with gauge readings around ~73.3% of its configured limit.
- Prometheus CPU and memory alert rules were successfully created; firing state was verified.

## 6. Alerting with PrometheusRule

```bash
kubectl apply --dry-run=server -f monitoring-lab/lab-alerts.yaml
kubectl apply -f monitoring-lab/lab-alerts.yaml
kubectl get prometheusrule -n monitoring
```

Both test rules trigger when a container's **CPU or memory utilization exceeds 70% of its configured limit for 2 minutes**. The Prometheus Operator discovers the `PrometheusRule` resource and updates Prometheus rule configuration. Prometheus evaluates the expressions; firing alerts are sent to Alertmanager. Notification channels require separate receiver/routing configuration.

The alert lifecycle is **Inactive → Pending → Firing** when a condition remains true long enough.

## 7. Cleanup

Before deleting the infrastructure, export any dashboards you want to retain. Check for leftover load balancers and persistent volumes.

```bash
kubectl delete namespace monitoring-lab --ignore-not-found
kubectl delete prometheusrule lab-resource-alerts -n monitoring --ignore-not-found
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring --ignore-not-found
terraform plan -destroy
terraform destroy
```

Inspect AWS for remaining resources and charges. Terraform only manages the resources in its state; it does not automatically clean up unrelated manually created resources.

## Security notes

- Never commit `terraform.tfstate`, `.tfvars`, AWS credentials, private keys, or passwords.
- Prefer a restricted EKS API CIDR and private access to monitoring interfaces.
- This is a **learning lab**, not a production-hardened infrastructure deployment.

## Key learning outcomes

- Provisioning EKS using Terraform and validating the cluster
- Managing Kubernetes monitoring tools with Helm
- Understanding scrape targets, container metrics, and PromQL
- Building custom Grafana visualizations
- Managing alerts declaratively with PrometheusRule and the Prometheus Operator
- Understanding alert evaluation and Alertmanager's routing role
- Safely cleaning up cloud lab infrastructure
