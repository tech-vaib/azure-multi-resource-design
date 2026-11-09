# Azure Terraform Reference Architecture

## Purpose

This repository is a reference implementation blueprint for managing Azure infrastructure across multiple subscriptions and multiple logical environments within the same subscription.

It is designed to support:

- Multiple application environments in one subscription (for example `dev-app1`, `dev-app2`, `qa-app1`, `qa-app2`).
- Reuse of selected shared infrastructure such as a VNet, subnet, VM, NAT Gateway, DNS, Key Vault, or shared platform service where technically and operationally appropriate.
- Creation of dedicated infrastructure for other resources.
- Independent Terraform states for resources with different ownership, lifecycle, retention, or upgrade requirements.
- Ordered deployment of multiple states for a complete new environment.
- Selective teardown while retaining shared or critical resources.
- Independent AKS and service upgrades.
- Migration of existing manually created or Terraform-managed resources without accidental recreation.

This is a **reference scaffold**, not a production-ready deployment. Pin and test provider versions, fill in environment-specific values, review networking/security, and validate plans before applying.

---

## 1. The key design: subscription, shared foundation, environment, application

Do not assume one subscription equals one environment. A subscription can contain several logical environments.

Use three scopes:

1. **Subscription scope** – subscription-level policies, role assignments, quotas, and shared governance.
2. **Subscription shared foundation** – infrastructure deliberately shared by multiple environments in that subscription, such as a VNet, shared subnets, NAT, DNS, or shared VM services.
3. **Environment/application scope** – resources owned by one logical environment or application, such as its AKS cluster, databases, Service Bus, APIM, ingress, and application infrastructure.

Example: two independent application environments inside the same Dev subscription.

```text
Azure tenant
└── Subscription: sub-dev
    ├── Shared foundation (one owner/state)
    │   ├── rg-dev-network
    │   │   ├── vnet-dev-shared
    │   │   ├── snet-dev-shared-services
    │   │   ├── snet-dev-app1
    │   │   ├── snet-dev-app2
    │   │   └── NAT / route tables / shared NSGs (as appropriate)
    │   └── rg-dev-shared-services
    │       ├── shared VM (only if its lifecycle/access model is truly shared)
    │       ├── shared DNS / monitoring / Key Vault (where approved)
    │       └── other approved shared services
    │
    ├── Environment: dev-app1
    │   ├── rg-dev-app1-aks       -> dedicated AKS (or shared AKS selected by config)
    │   ├── rg-dev-app1-data      -> Cosmos / PostgreSQL / Redis
    │   ├── rg-dev-app1-messaging -> Service Bus
    │   ├── rg-dev-app1-ingress   -> App Gateway + WAF
    │   └── rg-dev-app1-apps      -> app-specific resources
    │
    └── Environment: dev-app2
        ├── rg-dev-app2-aks
        ├── rg-dev-app2-data
        ├── rg-dev-app2-messaging
        ├── rg-dev-app2-ingress
        └── rg-dev-app2-apps
```

`dev-app1` and `dev-app2` can consume the same VNet or selected shared services, while creating their own AKS, databases, Service Bus, APIM, or ingress resources.

Do not share a VM merely because it exists. Share only when the VM's purpose, access controls, patching window, availability, capacity, and failure domain are suitable for all consumers. A shared VM is owned by the shared-foundation state; environment states consume its ID/private IP and must not manage it.

For Dev, Stage, and Prod subscriptions, normally maintain separate network foundations per subscription. A VNet is scoped to one subscription; VNet peering is used for connectivity between VNets/subscriptions.

### Important Azure resource-group rule

A subnet is a child of a VNet. It is managed in the VNet's Resource Group, not an application's Resource Group. Application resources can be in other Resource Groups and attach to that subnet, subject to Azure's network constraints.

---

## 2. Recommended repository layout

The repository separates reusable modules from deployable root configurations. Each deployable root directory is a separate Terraform state.

```text
azure-terraform/
├── README.md
├── versions.tf
├── modules/                         # Reusable building blocks; no backend blocks
│   ├── network-foundation/
│   ├── subnet/
│   ├── nsg/
│   ├── nat-gateway/
│   ├── virtual-machine/
│   ├── aks/
│   ├── application-gateway-waf/
│   ├── apim/
│   ├── cosmos-mongodb/
│   ├── postgresql/
│   ├── redis/
│   ├── service-bus/
│   ├── key-vault/
│   ├── private-endpoint/
│   └── monitoring/
│
├── live/                             # Root modules: each directory = one state
│   └── subscriptions/
│       └── dev/
│           ├── shared/
│           │   ├── 00-network-foundation/
│           │   ├── 01-shared-compute/
│           │   └── 02-shared-platform/
│           └── environments/
│               ├── app1/
│               │   ├── 10-network-attachments/
│               │   ├── 20-aks/
│               │   ├── 30-ingress/
│               │   ├── 40-apim/
│               │   ├── 50-cosmos/
│               │   ├── 51-postgresql/
│               │   ├── 52-redis/
│               │   ├── 53-service-bus/
│               │   └── 90-app-infrastructure/
│               └── app2/
│                   └── ... same pattern ...
│
├── env-config/                       # Non-secret environment configuration
│   └── dev/
│       ├── shared.tfvars
│       ├── app1.tfvars
│       └── app2.tfvars
│
├── orchestration/                    # Ordered deploy/destroy scripts
│   ├── deploy-env.sh
│   ├── destroy-env.sh
│   └── state-order-dev-app1.txt
│
└── docs/
    ├── state-ownership.md
    ├── migration-runbook.md
    ├── aks-upgrade-runbook.md
    └── retention-and-destroy.md
```

Replicate the same layout under `stage/` and `prod/`. Avoid copying module source; all live roots call the same versioned modules.

### State naming

Example remote backend keys:

```text
dev/shared/network-foundation.tfstate
dev/shared/shared-compute.tfstate
dev/environments/app1/aks.tfstate
dev/environments/app1/cosmos.tfstate
dev/environments/app2/aks.tfstate
```

A state key is not a workspace. Each live root has its own backend key and state ownership.

---

## 3. Which resources belong together?

Use lifecycle and ownership as the deciding factors, not simply resource type.

| State | Typical contents | Guidance |
|---|---|---|
| Shared network foundation | VNet, subnets, NAT, route tables | One state per subscription/network boundary; shared by multiple environments |
| Network security | NSGs and associations | May be combined with network foundation if same owner/lifecycle; otherwise separate |
| Shared compute | Truly shared VMs, NICs, disks | Separate from network; environment VMs belong to their environment |
| AKS | Cluster, node pools, identities and cluster settings | Separate state per cluster/environment; upgrade independently |
| Ingress | Application Gateway and associated WAF configuration/policy | Keep together when lifecycle is coupled |
| APIM | API Management | Separate state; independent lifecycle |
| Cosmos Mongo API | Cosmos account and data resources | Separate state; backup/retention important |
| PostgreSQL | Flexible server and databases | Separate state; independent maintenance/upgrade |
| Redis | Cache resources | Separate state |
| Service Bus | Namespace, queues, topics, subscriptions | Separate state |
| Shared platform | Key Vault, DNS, monitoring, shared identities | Split further only where ownership/lifecycle requires it |
| Application infrastructure | App-specific resources | Per environment/application |

Do not put AKS, APIM, and Application Gateway in one state merely because traffic flows between them. Their upgrade and replacement cycles differ.

NSG ownership must be unambiguous. Do not let both the shared network state and an application state manage the same NSG or subnet association.

---

## 4. Existing versus create: explicit configuration

Every reusable module/root configuration should use an explicit mode:

- `create`: this state creates and owns the resource.
- `existing`: look up and consume a resource owned elsewhere.
- `remote_state`: consume outputs from the Terraform state that owns the resource (preferred for resources managed by this repository).

Do not silently try a data source and fall back to creating a resource. A failed lookup should fail the plan; it must not unexpectedly create a second resource.

Example configuration:

```hcl
network = {
  mode                = "remote_state"
  state_key           = "dev/shared/network-foundation.tfstate"
  vnet_name           = "vnet-dev-shared"
  resource_group_name = "rg-dev-network"
  subnet_key          = "app1"
}
```

For an externally managed existing VNet:

```hcl
network = {
  mode                = "existing"
  vnet_name           = "vnet-corporate"
  resource_group_name = "rg-corporate-network"
  subnet_name         = "snet-app1"
}
```

For a new dedicated VNet:

```hcl
network = {
  mode          = "create"
  vnet_name     = "vnet-dev-app3"
  address_space = ["10.40.0.0/16"]
}
```

A resource consumed in `existing` or `remote_state` mode must not be declared as a managed `resource` in the consuming state.

### Shared VM example

If app1 and app2 use a shared VM:

- `live/subscriptions/dev/shared/01-shared-compute` creates and owns the VM.
- Each environment reads the VM ID/private IP using remote-state outputs or a data source.
- Environment teardown does not include the shared-compute state.

If app1 requires its own VM, create it in app1's compute state instead.

---

## 5. Terraform files in each live root

Each live root should contain a predictable set of files:

```text
main.tf          # Module calls and resource composition
variables.tf     # Inputs and validations
outputs.tf       # Values consumed by downstream states
providers.tf     # Provider configuration / subscription context
versions.tf      # Terraform and provider version constraints
backend.tf       # Azure backend declaration (backend config supplied at init)
terraform.tfvars # Non-secret defaults only; preferably pass env-specific tfvars
```

Do not put credentials or secrets in `.tfvars`, Git, plan output, or state unnecessarily. Use workload identity/OIDC or managed identity for CI/CD and Key Vault or secure pipeline variables for required secrets.

---

## 6. Example: shared network foundation root

This root creates the VNet, shared subnets, and NAT. It is applied once per subscription/network boundary.

`live/subscriptions/dev/shared/00-network-foundation/variables.tf`

```hcl
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "vnet_name" { type = string }
variable "address_space" { type = list(string) }

variable "subnets" {
  type = map(object({
    address_prefixes = list(string)
  }))
}

variable "create_nat_gateway" {
  type    = bool
  default = true
}
```

`main.tf` (illustrative module composition)

```hcl
module "network" {
  source              = "../../../../../../modules/network-foundation"
  location            = var.location
  resource_group_name = var.resource_group_name
  vnet_name           = var.vnet_name
  address_space       = var.address_space
  subnets             = var.subnets
  create_nat_gateway  = var.create_nat_gateway
}
```

`outputs.tf`

```hcl
output "vnet_id" {
  value = module.network.vnet_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}
```

`terraform.tfvars` example

```hcl
location            = "westus2"
resource_group_name = "rg-dev-network"
vnet_name            = "vnet-dev-shared"
address_space        = ["10.20.0.0/16"]

subnets = {
  shared_services = { address_prefixes = ["10.20.1.0/24"] }
  app1             = { address_prefixes = ["10.20.2.0/24"] }
  app2             = { address_prefixes = ["10.20.3.0/24"] }
  private_endpoints = { address_prefixes = ["10.20.4.0/24"] }
}

create_nat_gateway = true
```

The network module should create only the resources explicitly assigned to this state. It should also support adopting existing resources through a separately planned import workflow, not by making the same resource both a data source and managed resource.

---

## 7. Example: environment root reusing the shared VNet and creating its own AKS

`live/subscriptions/dev/environments/app1/20-aks/backend.tf`

```hcl
terraform {
  backend "azurerm" {}
}
```

`providers.tf`

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

`variables.tf`

```hcl
variable "subscription_id" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "aks_name" { type = string }
variable "kubernetes_version" { type = string }
variable "subnet_id" { type = string }
```

`main.tf`

```hcl
module "aks" {
  source              = "../../../../../modules/aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  name                = var.aks_name
  kubernetes_version  = var.kubernetes_version
  subnet_id           = var.subnet_id
}
```

The `subnet_id` should be passed from the network foundation state output or an approved data lookup. This AKS state must not create or own the shared VNet/subnet.

`outputs.tf`

```hcl
output "aks_id" {
  value = module.aks.aks_id
}

output "aks_name" {
  value = module.aks.aks_name
}
```

The module should define its own validated variables and outputs. The exact AKS implementation must account for the chosen network plugin, pod/service CIDRs, identity, private cluster requirements, node pools, and AzureRM provider version.

---

## 8. Per-environment reuse matrix

Use configuration to decide what is shared and what is dedicated. Do not create a new copy of every resource for every logical environment.

Example:

| Resource | app1 | app2 | app3 |
|---|---|---|---|
| VNet | Reuse shared | Reuse shared | Create dedicated |
| Subnet | Existing app1 subnet | Existing app2 subnet | Create new |
| NAT | Reuse shared | Reuse shared | Dedicated if required |
| VM | Reuse shared VM | Reuse shared VM | Create dedicated |
| AKS | Create dedicated | Create dedicated | Reuse shared cluster only if approved |
| Cosmos | Create dedicated | Reuse approved shared account | Create dedicated |
| PostgreSQL | Create dedicated | Create dedicated | Existing approved server |
| Redis | Reuse approved shared | Create dedicated | Create dedicated |
| Service Bus | Create dedicated | Create dedicated | Reuse approved shared namespace |

This is a conceptual example. Confirm that each service supports the required isolation, capacity, access and lifecycle model before sharing.

A shared resource must have one owner and one state. Environment configurations only consume it.

---

## 9. Ordered deployment of multiple states

A complete environment consists of several independently managed Terraform roots. Provide an orchestration script that applies them in dependency order.

Example order for app1:

```text
1. shared/00-network-foundation
2. shared/01-shared-compute             (if needed)
3. shared/02-shared-platform            (if needed)
4. environments/app1/10-network-attachments (only if it owns additional attachments)
5. environments/app1/20-aks
6. environments/app1/30-ingress
7. environments/app1/40-apim
8. environments/app1/50-cosmos
9. environments/app1/51-postgresql
10. environments/app1/52-redis
11. environments/app1/53-service-bus
12. environments/app1/90-app-infrastructure
```

Not every environment needs every state. The orchestrator must allow optional stages and must not create empty states for disabled services.

### Backend initialization

Use a separate backend key for every root. Example:

```bash
terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=stterraformstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=dev/environments/app1/aks.tfstate"
```

The storage account and container should be bootstrapped separately and protected.

### Example deployment script

`orchestration/deploy-env.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./orchestration/deploy-env.sh dev app1
#
# Configure subscription authentication and backend settings in CI/CD.
# This reference script expects the ordered state directories to exist.

SUBSCRIPTION="${1:?subscription folder required, e.g. dev}"
ENVIRONMENT="${2:?environment required, e.g. app1}"

ROOT="live/subscriptions/${SUBSCRIPTION}"
SHARED="${ROOT}/shared"
ENV="${ROOT}/environments/${ENVIRONMENT}"

STAGES=(
  "${SHARED}/00-network-foundation"
  "${SHARED}/01-shared-compute"
  "${SHARED}/02-shared-platform"
  "${ENV}/20-aks"
  "${ENV}/30-ingress"
  "${ENV}/40-apim"
  "${ENV}/50-cosmos"
  "${ENV}/51-postgresql"
  "${ENV}/52-redis"
  "${ENV}/53-service-bus"
  "${ENV}/90-app-infrastructure"
)

for DIR in "${STAGES[@]}"; do
  # Optional state directories may not exist or may be disabled.
  if [[ ! -d "${DIR}" ]]; then
    echo "Skipping absent stage: ${DIR}"
    continue
  fi

  echo "=== Planning ${DIR} ==="
  terraform -chdir="${DIR}" init
  terraform -chdir="${DIR}" validate
  terraform -chdir="${DIR}" plan -out=tfplan

  echo "Review the plan and approve before applying."
  read -r -p "Apply ${DIR}? Type yes: " APPROVAL
  [[ "${APPROVAL}" == "yes" ]] || { echo "Stopped."; exit 1; }

  terraform -chdir="${DIR}" apply tfplan
done
```

For production, replace interactive prompts with a protected CI/CD approval gate. Supply backend configuration deterministically for every stage. Do not store generated plan files as long-lived artifacts; plans can contain sensitive values.

### Important orchestration requirement

The script is a starting point. The engineering team must implement:
- Explicit stage enablement from environment configuration.
- Correct backend key selection for each state.
- Subscription verification before each stage.
- Dependency checks and outputs handoff.
- Plan review and approval.
- Retry/resume behavior.
- A deployment manifest recording which states were applied.
- A way to deploy only selected stages when prerequisites already exist.

Do not blindly apply every state in a directory tree.

---

## 10. Teardown and retention

Teardown should use the reverse dependency order and should be scope-aware.

For app1, a normal environment teardown might remove:

```text
90-app-infrastructure
30-ingress
40-apim
20-aks
50-cosmos       # only if approved
51-postgresql   # only if approved
52-redis        # only if approved
53-service-bus  # only if approved
```

It must not destroy shared states such as:

```text
shared/00-network-foundation
shared/01-shared-compute
shared/02-shared-platform
```

unless an explicit shared-foundation decommission operation is approved after verifying no consumers remain.

Implement these concepts:

- `shared`: never included in routine environment teardown.
- `environment`: eligible for environment teardown after approval.
- `critical`: protected with appropriate Terraform lifecycle and/or Azure locks.
- `retained`: must be preserved and transferred or detached through a documented state operation.
- `disposable`: may be destroyed as part of environment teardown.

`prevent_destroy` is a static lifecycle guard and must remain in the resource configuration. Azure `CanNotDelete` locks are an additional Azure-side safeguard. Locks can themselves block Terraform deletion until deliberately removed.

If a resource must remain in Azure but leave a state, use a controlled `removed` block with `destroy = false` or a reviewed state migration. Then ensure exactly one intended state owns it (or document that it is deliberately unmanaged). Do not simply set a `create = false` or `enabled = false` variable on an already-managed resource and assume it will be retained.

Always back up state and review a destroy plan before execution.

---

## 11. Module version and maintenance strategy

Modules are reusable code; live roots are deployments.

Recommended module practices:

1. Keep each module focused on one service or cohesive capability.
2. Define `variables.tf`, `main.tf`, `outputs.tf`, `versions.tf`, and a module README.
3. Validate inputs and expose stable outputs.
4. Avoid embedding subscription/environment-specific values.
5. Pin Terraform and AzureRM provider versions in root configurations.
6. Publish stable module releases using Git tags or an internal module registry.
7. Pin live roots to a released module version or immutable Git ref.
8. Test module changes in a sandbox/Dev root before Stage and Prod.
9. Use semantic versioning:
   - Patch: fixes that do not change module interface.
   - Minor: backward-compatible features.
   - Major: breaking interface or behavior changes.
10. Do not let a change to a shared module automatically force all environments to upgrade without review.

Example module reference:

```hcl
module "aks" {
  source = "git::https://example.com/platform/azure-terraform-modules.git//modules/aks?ref=v1.4.0"
  # inputs...
}
```

Replace the example URL with the organization's actual repository or registry.

For a single monorepo, use a tested immutable Git commit/tag reference where supported. Avoid using an unpinned `main` branch for production.

Maintain a module compatibility matrix:

| Module | Tested Terraform | Tested AzureRM | Release |
|---|---|---|---|
| networking | team-approved version | team-approved version | v1.x |
| aks | team-approved version | team-approved version | v1.x |
| cosmos-mongodb | team-approved version | team-approved version | v1.x |

---

## 12. Upgrade strategy

### Provider upgrades

- Pin provider versions.
- Upgrade in a dedicated pull request.
- Review provider changelog and breaking changes.
- Run formatting, validation, security checks and plans for affected roots.
- Test in Dev, then Stage, then Prod.
- Commit the updated dependency lock file.

### Module upgrades

- Release a new module version.
- Update only the live roots that should consume it.
- Plan each state independently.
- Avoid upgrading every environment at once.

### AKS upgrades

Keep AKS in its own state. Upgrade Dev, validate workloads, then Stage, then Prod. Review Kubernetes version support, deprecated APIs, node pool surge capacity, PodDisruptionBudgets, subnet/IP capacity, ingress, CSI/storage, DNS and maintenance windows.

### Data service upgrades

Review service-specific supported upgrade paths and backup/restore requirements. Do not assume every SKU or major version can be upgraded in place.

---

## 13. Migration of existing resources and states

For existing infrastructure:

1. Inventory Azure resources and current state ownership.
2. Back up all state files.
3. Map each Azure resource to exactly one target state.
4. Import unmanaged resources or move existing state ownership using a reviewed procedure.
5. Use `terraform plan` to confirm no unexpected create, replacement or deletion.
6. Test in Dev.
7. Migrate Stage and Prod in controlled windows.
8. Preserve a rollback path.

Never let two Terraform states manage the same physical resource. Never delete state files as a shortcut. Use `terraform state mv`, import blocks, or `removed` blocks as appropriate to the specific migration.

---

## 14. Security, backend and CI/CD

Use an Azure Storage Account backend with:
- Blob versioning and soft delete.
- Appropriate redundancy and backup.
- Entra ID authentication.
- OIDC/workload identity or managed identity for pipelines.
- Least-privilege RBAC.
- Private endpoint/network restrictions where practical.
- Separate keys per state.
- State access auditing.

CI/CD must run:
1. `terraform fmt -check`
2. `terraform init`
3. `terraform validate`
4. Security/policy scanning
5. `terraform plan`
6. Plan review
7. Approval
8. `terraform apply`
9. Post-deployment validation

Use a separate protected destroy pipeline.

---

## 15. Required acceptance tests

The engineering team must demonstrate:

1. Create shared VNet and subnets in the Dev subscription.
2. Deploy app1 and app2 in the same subscription, both reusing the shared VNet but using different subnets.
3. Configure app1 to create its own AKS and app2 to reuse an approved shared AKS, without duplicate ownership.
4. Configure one environment to reuse a shared VM and another to create a dedicated VM.
5. Create dedicated Cosmos/PostgreSQL/Redis/Service Bus resources for one environment.
6. Reuse selected existing data/messaging resources in another environment.
7. Deploy a complete new environment by applying states in dependency order.
8. Resume deployment after a failed stage without recreating completed infrastructure.
9. Destroy app1 while app2 and shared networking remain operational.
10. Retain a selected database while decommissioning an environment, using a documented state ownership process.
11. Upgrade AKS independently of APIM and ingress.
12. Upgrade a module in Dev, validate, and promote to Stage/Prod.
13. Import a manually created resource without recreating it.
14. Move a resource between Terraform states without deleting it.
15. Verify that protected resources cannot be accidentally deleted.

---

## 16. Official references

- Terraform state: https://developer.hashicorp.com/terraform/language/state
- Terraform refactoring and moved blocks: https://developer.hashicorp.com/terraform/language/modules/develop/refactoring
- Terraform removed blocks: https://developer.hashicorp.com/terraform/language/block/removed
- Terraform lifecycle meta-arguments: https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
- Terraform module development: https://developer.hashicorp.com/terraform/language/modules/develop
- AzureRM provider: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- Azure resource locks: https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources
- Azure VNet design: https://learn.microsoft.com/azure/virtual-network/virtual-networks-udr-overview

---

## Final architecture rule

**Shared resources are created once in shared-foundation states. Each logical environment has its own deployable root states and can explicitly reuse shared resources or create dedicated resources. Every state has a clear owner, every deployment has an ordered dependency plan, and every teardown has an explicit retention policy.**

The goal is not merely to create infrastructure with Terraform. The goal is to make onboarding, migration, upgrades, reuse, and decommissioning safe and repeatable.
