# Migration plan: magnum k8s_fedora_coreos_v1 -> magnum-capi-helm

The legacy Heat-based Magnum driver in 2026.1 is effectively unmaintained against modern image streams (broken hyperkube/etcd/flannel image tags on docker.io, FCOS path expectations from 2020). The upstream-namespaced replacement is `openstack/magnum-capi-helm` (StackHPC-led, declared replacement in Magnum 2026.1 docs).

## Architecture

Two k8s control planes:

1. **Management cluster** - a long-lived 3+3 HA k8s on this OpenStack itself, running CAPI core + CAPO (cluster-api-provider-openstack) + cert-manager + cluster-api-addon-provider. Provisioned via `azimuth-cloud/azimuth-config`'s `capi-mgmt-example` (seed-then-HA model: a k3s VM bootstraps the controllers, controllers then reconcile a real HA cluster onto OpenStack, k3s is torn down).

2. **Tenant clusters** - one per Magnum cluster. Each gets its own private Neutron net + router + Octavia LB for the apiserver + per-cluster Keystone application credential (not legacy trusts - app-creds work with cloud-provider-openstack).

When a tenant runs `openstack coe cluster create`, the magnum_conductor calls `helm upgrade --install openstack-cluster` against the management cluster's kubeconfig, helm renders CAPI CRs, CAPO drives Nova/Neutron/Octavia.

## Prerequisites already in place

- Octavia LBaaS: verified end-to-end (see Octavia section of main README)
- Barbican: deployed
- Magnum: deployed
- Cinder LVM: deployed (Cinder CSI will use this in tenant clusters)
- Keystone application credentials: supported
- Glance: deployed

## Day-1 work to do

1. **Mirror ~30 container images into Nexus** (group `docker.cloudinative.com`):
   - cert-manager controller/webhook/cainjector/acmesolver (quay.io/jetstack)
   - cluster-api core + kubeadm-bootstrap + kubeadm-control-plane controllers (registry.k8s.io/cluster-api/*)
   - capo-openstack-controller (registry.k8s.io/capi-openstack/*)
   - cluster-api-addon-provider (ghcr.io/azimuth-cloud/*)
   - kube-{apiserver,controller-manager,scheduler,proxy,etcd,coredns,pause} for each supported k8s minor (registry.k8s.io)
   - Calico full set (docker.io/calico/*) OR Cilium set (quay.io/cilium/*)
   - openstack-cloud-controller-manager (registry.k8s.io/provider-os/*)
   - cinder-csi-plugin + csi sidecars (registry.k8s.io/provider-os/, sig-storage/*)
   - cluster-autoscaler (registry.k8s.io/autoscaling/*)
   - capi-janitor-openstack (ghcr.io/azimuth-cloud/*)
   - Optional: k8s-keystone-auth (registry.k8s.io/provider-os/*) if you enable keystone-token kubectl auth

2. **Mirror Helm charts into Nexus** (Nexus Pro supports OCI/Helm hosted repos):
   - `openstack-cluster` from `azimuth-cloud/capi-helm-charts` (the Magnum-invoked chart)
   - `cluster-addons` (sibling chart, wraps the in-cluster add-ons)
   - Subchart sources: cilium, tigera-operator (Calico), openstack-cloud-controller-manager, openstack-cinder-csi, cluster-autoscaler, kube-prometheus-stack, metrics-server, ingress-nginx

3. **Bake an azimuth-images Ubuntu 24.04 qcow2** with `/etc/containerd/certs.d/` host-overlay entries pointing docker.io/quay.io/registry.k8s.io/gcr.io/ghcr.io to *.cloudinative.com, kubelet/kubeadm/kubectl/containerd preinstalled.

4. **Build a custom kolla magnum image** (or use kolla-ansible's `/etc/kolla/config/magnum/Dockerfile` overlay):
   ```Dockerfile
   FROM docker-quay.cloudinative.com/openstack.kolla/magnum-base:2026.1-ubuntu-noble
   RUN curl -fsSLo /usr/local/bin/helm https://get.helm.sh/helm-v3.13.3-linux-amd64.tar.gz && \
       tar xzf helm-v3.13.3-linux-amd64.tar.gz -C /tmp && \
       install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
   RUN pip install --no-cache-dir magnum-capi-helm
   ```

5. **Stand up the management cluster** via `azimuth-cloud/azimuth-config`:
   ```bash
   git clone https://github.com/azimuth-cloud/azimuth-config
   cp -r azimuth-config/environments/capi-mgmt-example environments/cloudinative-capi-mgmt
   # edit cluster-spec to point at cloudinative-public network, set the floating-network etc
   ansible-playbook -e config_environment=cloudinative-capi-mgmt seed.yml
   ansible-playbook -e config_environment=cloudinative-capi-mgmt provision.yml
   ```

6. **Wire magnum to the management cluster**:
   - Drop the management cluster kubeconfig (ansible-vaulted) at `/etc/kolla/config/magnum/kubeconfig`
   - Add to globals.yml:
     ```yaml
     magnum_enabled_drivers: ['k8s_capi_helm_v1']
     ```
   - Add to /etc/kolla/config/magnum.conf overlay:
     ```ini
     [DEFAULT]
     enabled_drivers = k8s_capi_helm_v1

     [capi_helm]
     kubeconfig_file = /etc/magnum/kubeconfig
     default_helm_repository = https://helm.cloudinative.com/repository/azimuth-capi-charts
     ```

7. **Define cluster templates** pinned to specific kube_tag + chart-version pairs:
   ```bash
   openstack coe cluster template create \
     --image cloudinative-capi-ubuntu-2404-1.32.4 \
     --keypair cloudinative-key \
     --external-network cloudinative-public \
     --flavor cloudinative-medium \
     --master-flavor cloudinative-medium \
     --coe kubernetes \
     --labels kube_tag=v1.32.4,capi_helm_chart_version=0.14.2 \
     cloudinative-k8s-1.32
   ```

## Open Magnum bugs to watch

- LP#2126841 (driver registration regression on fresh deploys)
- LP#2099997 (multi-network cluster template breaks)
- LP#2098002 (autoscale min=0)
- LP#2098740 (KubeadmControlPlane bootstrap edge case)

## Estimated effort

1-2 days for first end-to-end working tenant cluster, plus an ongoing maintenance commitment to mirror every new image when chart versions move.
