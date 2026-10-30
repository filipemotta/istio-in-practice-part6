# Istio, Hands-On, Final Part: GKE and EKS in One Mesh: How Your Calls Cross Clouds and When They Shouldn’t

Companion repository for *Istio, Hands-On*, the final part: one Istio mesh across GKE and EKS,
multi-primary on two networks, built with Terraform and tested end to end in both clouds.

The lab proves the article's claim with assertions, not screenshots: a multi-cluster mesh is
an agreement on three things (one root of trust, the names of clusters and networks, and
each control plane reading the other's API), and once the agreement is in place Istio
spreads traffic across the clouds until you tell it otherwise.

> **Read this first: the public endpoints are for the lab only.** There is no VPN between
> the two clouds here. The two Kubernetes API servers and the two east-west gateways have
> public addresses, each one allow-listed to the operator and to the other cloud's NAT
> address, and the data between the gateways is mTLS end to end. That is enough for a lab
> you create and destroy in an hour; it is not the production design. In production the
> clouds talk over a private link: Google Cloud HA VPN to AWS Site-to-Site VPN (four
> tunnels, BGP through Cloud Router, a transit gateway on the AWS side, 99.99% SLA) or
> Cross-Cloud Interconnect, with private API endpoints and internal load balancers for the
> east-west gateways. See [Production shape](#production-shape).

## What it builds

```
                 Google Cloud, us-east4                         AWS, us-east-1
   ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
   │ GKE 1.36  (cluster gke-us-east4,         │   │ EKS 1.36  (cluster eks-us-east-1,        │
   │            network network-gcp)          │   │            network network-aws)          │
   │                                          │   │                                          │
   │  istiod ── reads the EKS API ───────────────────▶ EKS API (allow-list: operator,      │
   │                                          │   │                   GCP Cloud NAT address) │
   │  GKE API ◀────────────────────────────────────── reads the GKE API ── istiod          │
   │  (allow-list: operator, AWS NAT address) │   │                                          │
   │                                          │   │                                          │
   │  payments-api ──▶ fraud-check (local)    │   │  fraud-check                             │
   │        │                                 │   │       ▲                                  │
   │        └── mTLS ──▶ Cloud NAT ──────────────────▶ east-west gateway :15443 (NLB,      │
   │                                          │   │       only the GCP NAT address)          │
   │  east-west gateway :15443 (only the      │   │                                          │
   │  AWS NAT address)                        │   │                                          │
   └─────────────────────────────────────────┘   └─────────────────────────────────────────┘
```

- Terraform, six stacks: `terraform/{aws,gcp}/{00-remote-backend,01-networking,02-eks|02-gke}`.
- Istio 1.31.3, one istiod per cluster (multi-primary), `meshID: mesh-payments`.
- The `payments` namespace on both sides: `payments-api` (the caller) and `fraud-check` on
  GKE, a second `fraud-check` on EKS. Same namespace and Service name, so with namespace
  sameness the mesh sees one service with endpoints in two clouds. `fraud-check` is
  fortio's echo server; every answer carries `x-served-by: gke-us-east4` or
  `x-served-by: eks-us-east-1`, which is how the lab counts where each call went.

## Pinned versions

- Istio 1.31.3 (istioctl downloaded into `./bin` with its SHA-256 checked)
- kubectl v1.37.1 (same)
- Kubernetes 1.36 on both clusters (EKS `1.36`, GKE release channel REGULAR)
- Terraform >= 1.11 (S3 native state locking), providers `hashicorp/aws ~> 6.70`, `hashicorp/google ~> 8.9`
- fortio 1.75.3, curl 8.22.0 (lab workloads)

## Prerequisites

- An AWS account and a Google Cloud project with billing, both yours to create and destroy
  resources in. **The lab is billable**: about US$ 0.72 per hour with everything up
  (Infracost, list prices); a full run takes about an hour including the teardown.
- `aws` CLI with a profile for that account, `gcloud` logged in with the
  `gke-gcloud-auth-plugin` component, `terraform`, `jq`, `curl`, `openssl`, bash 4 or later.
- The Compute Engine, Kubernetes Engine and IAM APIs are enabled by `gcp/00-remote-backend`.

## Run the lab

```bash
export AWS_PROFILE=<your profile>
export GCP_PROJECT=<your project ID>
export GCP_ACCOUNT=<google account>        # optional, when gcloud has several logged in

bash scripts/test-all.sh                   # everything, then the teardown
KEEP=1 bash scripts/test-all.sh            # keep the clouds up afterwards
bash scripts/teardown.sh                   # destroy everything, then check for leftovers
```

Every script refuses to run unless its two kube contexts point at the two clusters this lab
created (it compares them with the endpoints the cloud APIs report). The lab writes its own
kubeconfig, `out/kubeconfig`, with exactly two contexts (`gke-p6`, `eks-p6`); your
`~/.kube/config` is never read or written. Every `gcloud` call is pinned to `GCP_PROJECT`,
whatever your gcloud default project is.

## The steps

| Script | What it does | What it asserts |
|---|---|---|
| `01-infra.sh` | Terraform, stack by stack; the two clusters in parallel; the lab kubeconfig | nodes Ready, Kubernetes 1.36, each API allow-list is exactly the operator and the other cloud's NAT address, private nodes |
| `02-istio.sh` | plugin CA per cluster (**a different root per team**), network label, istiod, east-west gateway, `cross-network-gateway` | istiod 1.31.3, network labels, each east-west load balancer accepts only the peer NAT address and exposes only 15021 and 15443, the gateway forwards only inside its own network, the two roots differ |
| `03-discovery.sh` | apps, remote secrets both ways | both remote clusters `synced`; what the remote secret grants; the EKS fraud-check appears in the GKE caller's proxy as the EKS gateway on 15443; with different roots every call to EKS fails, and the caller's proxy says why |
| `04-trust.sh` | reissue the EKS intermediate from the GKE team's root, restart istiod and the EKS proxies | one root on both sides; the same calls now succeed |
| `05-locality.sh` | 200 calls with no rule, with a failover rule without outlier detection, with the full rule | traffic crosses clouds by default; the rule without outlier detection is accepted with a warning and changes nothing that matters; the full rule keeps 200 of 200 local |
| `06-failover.sh` | the GKE fraud-check answers 503 | with the default `maxEjectionPercent` nothing moves; with 100% the calls move to EKS; once the repaired pod is Ready they come back |
| `07-exposure.sh` | probes the east-west gateways from this machine and from GKE | outsiders get no answer; the peer NAT address connects and is still refused without mesh mTLS |

Pass `KEEP=1` and run any step again on its own (`bash scripts/05-locality.sh`), except
`02-istio.sh`, which installs the per-team roots and is meant to run once per cluster pair.

## Results of the last run

Clean run from empty accounts, 2026-10-28: Terraform apply, the seven steps, then the
teardown. 58 of 58 assertions passed in 1724 s (Terraform alone 1061 s), and the teardown
found the clouds clean in 11 of 11 checks; 2724 s wall time in total.

- **Discovery**: right after both remote clusters reported `synced`, the caller's proxy
  listed the EKS fraud-check by its **pod IP** (`10.10.11.90:8080`), unreachable from GKE.
  Sixty seconds later, once the DNS name of the new NLB resolved, it was replaced by the
  two NLB addresses on 15443. Istio publishes a remote-network endpoint directly while that
  network has no known gateway (`EndpointsByNetworkFilter`, `ep_filters.go`), which is why
  `03-discovery.sh` waits for the gateway before measuring anything.
- **Different roots**: 0 of 10 calls to EKS succeeded (8 × 503 from the caller's own proxy,
  2 timeouts, most likely right after the local pod went away). The proxy's connection log says why:
  `CERTIFICATE_VERIFY_FAILED ... self signed certificate in certificate chain`.
- **One root**: 20 of 20 calls served by EKS, median 9 ms GKE → EKS.
- **No rule**: 100 calls served by GKE, 100 by EKS (medians 4 ms and 8 ms). Earlier runs
  gave 125/75 and 127/73: the local pod and the remote gateway carry the same total weight,
  not an exact half of the calls.
- **Failover rule without outlier detection**: accepted with
  `Warning: outlier detection policy must be provided for failover`; still 100/100.
- **Full locality rule**: 200 of 200 in us-east4; priorities `8080:0`, `15443:1`.
- **Broken local fraud-check, default `maxEjectionPercent` (10%)**: 50 of 50 calls got the
  local 503, the endpoint was never ejected.
- **Same failure, `maxEjectionPercent: 100`**: 199 calls served by EKS, one 503 before the
  ejection. The repair is a rollout, so the repaired pod is a new endpoint and 200 of 200
  calls were back in us-east4 once it was Ready (the lab does not show an ejected host
  returning after `baseEjectionTime`).
- **Exposure**: neither gateway answers this machine; the GKE NAT address reaches the EKS
  gateway, which still refuses a client without mesh mTLS.

## Production shape

What this lab does publicly, a production mesh across GCP and AWS does privately:

- **Link**: HA VPN on the Google Cloud side and two Site-to-Site VPN connections on the AWS
  side (four tunnels, BGP through Cloud Router; a transit gateway rather than a virtual
  private gateway, so traffic spreads across the tunnels), or Cross-Cloud Interconnect.
- **API servers**: private endpoints only (EKS `endpoint_public_access = false`, GKE private
  endpoint), reachable over the link. Each istiod still reads the other cluster's API.
- **East-west gateways**: internal load balancers
  (`service.beta.kubernetes.io/aws-load-balancer-scheme: internal` with the AWS Load
  Balancer Controller; `networking.gke.io/load-balancer-type: Internal` on GKE).
- **Root CA**: offline or in a KMS/HSM, never on a laptop; intermediates per cluster, as
  here.
- **Remote secrets**: the token in each one belongs to a service account that can read
  every Secret of the other cluster (the reader role Istio installs; `03-discovery.sh`
  shows it). Treat the remote secret like a credential to the whole cluster.

The mesh configuration in this repository (`istio/`, `apps/`, `mesh/`) does not change
between the two shapes; only the addresses and load balancer annotations do.

## Layout

```
.
├── terraform/
│   ├── aws/{00-remote-backend,01-networking,02-eks}   # S3 state, VPC + NAT, EKS
│   └── gcp/{00-remote-backend,01-networking,02-gke}   # GCS state, VPC + Cloud NAT, GKE
├── istio/        # IstioOperator per cluster, east-west gateway template, cross-network Gateway
├── apps/         # payments namespace on each side
├── mesh/         # the three DestinationRules of steps 5 and 6
├── scripts/      # lib.sh, certs.sh, 01..07, test-all.sh, teardown.sh
├── tools/        # install-cli.sh (istioctl, kubectl into ./bin, checksums verified)
├── validate.sh   # static checks: terraform fmt/validate, kubeconform, shellcheck
└── .github/workflows/validate.yml
```

## Terraform conventions

The stacks follow one set of conventions: numbered stacks with their own state in a remote
backend (S3 with native locking, GCS), one variable object per domain with inline defaults,
`this`/`main` labels, `count` for plural resources, only `Name` as a per-resource tag
(global tags and labels come from the provider), names shaped
`<type>-istio-p6-<condensed region>`, one file per resource group, whole objects as
outputs, cross-stack reads through `terraform_remote_state`. Three things are adapted to a
throwaway lab and marked in the code:

- **Identity**: the operator's credentials (`AWS_PROFILE`, `gcloud` token). The provider
  still takes an optional role (`assume_role.role_arn`) or service account
  (`impersonation.service_account`), which is what a production repository sets per
  workspace.
- **Backend**: partial configuration, because the bucket names carry the account and project
  IDs; `scripts/lib.sh` passes them at `terraform init`.
- **`00-remote-backend`** keeps its own state locally and is destroyed last.

## CI

`.github/workflows/validate.yml` runs `validate.sh` on every push and pull request. The lab
itself is not run in CI: it creates billable resources in two clouds, and this repository
holds no cloud credentials.

## License

MIT, see [LICENSE](LICENSE).
