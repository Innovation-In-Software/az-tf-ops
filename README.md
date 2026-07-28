# az-tf-ops

Summit Retail's infrastructure repository for the **Orders** platform.

One Git repository per high-level solution. This is that repository for Orders.
Summit's shared Terraform modules live separately, in
[`az-tf-ops-modules`](https://github.com/Innovation-In-Software/az-tf-ops-modules).

## How this repository is used in class

You will work in **two** copies of this repository:

| Copy | When | What for |
|---|---|---|
| `Innovation-In-Software/az-tf-ops` | Lab 2 only | The shared practice repository. Branch, commit, and open a pull request here, and review a teammate's |
| `<you>/az-tf-ops-<your-username>` | Labs 3 to 12 | Your own copy, made with **Use this template**. Everything you build lives here |

You need your own copy because from Lab 10 on you store credentials in it, run
pipelines from it, and set the rules on its `main` branch. Twenty people cannot
do that to one repository.

## Layout

```
az-tf-ops/
  main.tf                Labs 3 and 4 only. Lab 5 moves this into environments/dev/
  environments/          one directory per environment, created in Lab 5
    dev/                 Lab 5 onward
    prod/                Lab 5 onward
    legacy-reporting/    Lab 9, imported rather than created
  scripts/               bootstrap scripts, see below
  docs/
    naming-and-tagging.md
  students/              Lab 2 exercise
  .github/workflows/     Lab 10
```

**Labs 3 and 4 work at the repository root.** You write a single `main.tf` there
and apply it, which keeps the first two Terraform labs about Terraform rather
than about directory layout.

**Lab 5 introduces `environments/`** and moves that configuration into
`environments/dev/`. From then on, each environment directory is its own
**root module**: its own `terraform init`, its own backend, its own state file,
its own `plan` and `apply`. Once you are past Lab 5, run Terraform from inside
an environment directory, never from the repository root.

## Scripts

These create the things Terraform cannot manage for itself. Run them from the
repository root.

| Script | Lab | What it does |
|---|---|---|
| `scripts/bootstrap-backend.ps1` | 5 | Storage account and container for Terraform state |
| `scripts/seed-key-vault.ps1` | 8 | Key Vaults and the VM admin password secret |
| `scripts/seed-legacy-reporting.ps1` | 9 | The hand-built environment you will import |
| `scripts/create-service-principal.ps1` | 10 | The pipeline's Azure identity and its GitHub secrets |
| `scripts/destroy-all.ps1` | 12 | Tears everything down, in the right order |

All take `-Suffix <your suffix>`. Run any of them with `-?` for full help.

## Conventions

Read [`docs/naming-and-tagging.md`](docs/naming-and-tagging.md) before you write
any resource.

## Working agreement

- Nobody commits to `main`. Branch, then open a pull request
- Every change gets a review before it merges
- `terraform fmt` before every commit
- No secrets in the repository. Credentials go in Azure Key Vault or GitHub
  Actions secrets
- Pin everything: Terraform version, provider version, module version
- Read the plan before you apply
