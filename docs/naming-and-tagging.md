# Naming and Tagging

Summit's conventions. Follow them even when it feels pedantic: consistency is
what lets you find a resource, attribute a cost, and spot the one somebody
created by hand.

## Naming pattern

```
<type>-<org>-<solution>-<environment>
```

| Resource | Name |
|---|---|
| Resource group | `rg-summit-orders-dev` |
| Virtual network | `vnet-summit-orders-dev` |
| Network security group | `nsg-summit-orders-dev` |
| Public IP | `pip-summit-orders-dev` |
| Network interface | `nic-summit-orders-dev` |
| Virtual machine | `vm-summit-orders-dev` |

Subnets are scoped inside their virtual network, so they use a short name that
describes their role: `snet-app`, `snet-data`.

### Where the pattern cannot apply

Two Azure resource types have naming rules that override the convention. Both
are **globally unique across all of Azure**, so they take a short suffix.

| Resource | Rule | Name |
|---|---|---|
| Storage account | 3-24 characters, lowercase letters and digits only, no hyphens | `stsummitordersdev<suffix>` |
| Key Vault | 3-24 characters, alphanumeric and hyphens, must start with a letter | `kv-summit-dev-<suffix>` |

In class, `<suffix>` is your 4-character student suffix. At Summit it would be a
short region or account code.

### Multi-region

Append the region when a solution spans more than one:
`vnet-summit-orders-prod-eastus`. Do not add it while everything is in one
region; it is noise until it is not.

## Tags

Four tags on everything that supports them.

| Tag | Value | Why |
|---|---|---|
| `environment` | `dev`, `staging`, `prod` | Filtering, policy, cost |
| `solution` | `orders`, `reporting` | Which platform owns it |
| `owner` | `ops-team` | Who to call |
| `managed_by` | `terraform` | Tells the next person not to edit it by hand |

Add `cost_center` where finance needs it, and `role` on individual resources
where it clarifies things (`role = "app-server"`).

Define them **once**, in a `locals` block, and reference that everywhere:

```hcl
locals {
  tags = {
    environment = var.environment
    solution    = var.solution
    owner       = var.owner
    managed_by  = "terraform"
  }
}
```

Use `merge()` to add to the set without redefining it:

```hcl
tags = merge(local.tags, { role = "app-server" })
```

Tag keys are case sensitive in Azure. `Owner` and `owner` are two different
tags, and a subscription with both is a subscription nobody can report on. That
is not hypothetical: `rg-legacy-reporting` in Lab 9 has exactly that problem.

## Resource groups

| Resource group | Holds | Managed by |
|---|---|---|
| `rg-summit-orders-dev` | The dev environment | Terraform, `environments/dev` |
| `rg-summit-orders-prod` | The prod environment | Terraform, `environments/prod` |
| `rg-summit-tfstate` | Terraform state storage | Bootstrap script. **Never destroy** |
| `rg-summit-security` | Key Vaults | Bootstrap script. Security team |
| `rg-legacy-reporting` | The inherited estate | Terraform, `environments/legacy-reporting` |

State and secrets live outside the environments on purpose. A `terraform
destroy` in an environment deletes its resource group and everything in it, and
neither your state nor your credentials should be in that blast radius.

## Address ranges

| Environment | Address space | App subnet |
|---|---|---|
| `dev` | `10.10.0.0/16` | `10.10.1.0/24` |
| `prod` | `10.20.0.0/16` | `10.20.1.0/24`, data `10.20.2.0/24` |
| `legacy-reporting` | `172.16.0.0/16` | `172.16.10.0/24` |

Non-overlapping, so any two of them could be peered later without renumbering.

Derive subnets with `cidrsubnet()` rather than writing them twice:

```hcl
address_prefixes = [cidrsubnet(var.vnet_address_space[0], 8, 1)]
```
