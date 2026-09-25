# aws-team-tools-b1

The team's own tools, on the platform built by core (`aws-core-infra-b1`): **DbGate** and **CloudBeaver** (Community), to browse and query the databases. They are for the team, never for customers, and run on servers of their own, apart from the customer fleets.

```text
                  development, staging                          production
  person ─► dbgate.<domain> / cloudbeaver.<domain>        person ─► Session Manager tunnel
              │  CloudFront                                          │  (AWS sign-in)
              ▼                                                      ▼
        private load balancer ─► Cognito sign-in              the tools server
              ▼                                                      │
        the tools server (spot, private subnets, team-tools group)   │
              ▼                                                      ▼
        each person signs in to the database as themselves ◄─────────┘
```

## What it builds, per environment

| | |
| --- | --- |
| Servers | One disposable spot server (t3.medium or t3a.medium), on core's golden image, in the private subnets, wearing core's **team-tools** security group (which the databases admit) and its own |
| Programs | DbGate (port 3000) and CloudBeaver (port 8978), pinned in `tools/images.json`, pulled from Docker Hub at each start |
| Connections | Prepared from core's contract: development's database host (all engines in `development_engines`, native ports, no TLS); staging's and production's managed databases, TLS verified against AWS's RDS bundle (downloaded at start, refused unless its SHA-256 is `tools/rds-bundle.sha256`) |
| Schedule | `tools/schedule.json`, Lagos time: development and production weekdays 08:00-19:00, staging weekends 08:00-19:00 |
| Start button | The **Start tools** workflow: starts one now and switches it off two hours later, unless the schedule takes over first |
| Web addresses | Development and staging only: `dbgate.<domain>` and `cloudbeaver.<domain>` on the private load balancer, behind core's Cognito sign-in (its front door) |
| Production | No web address: a Session Manager tunnel (`docs/tunnel.md`) |

Nobody's database password is ever stored: DbGate asks for the username and password at every connection (`askUser`), and CloudBeaver saves no credentials. Each person uses their own login: a service's agent (`<service>.<name>`) or the platform list (`platform.<name>`).

CloudBeaver configures itself with an administrator at every start (otherwise its setup page would make the first visitor the administrator). Nobody needs it day to day; its password is random, readable by root on the server only: `sudo cat /root/cloudbeaver-admin-password` in a Session Manager session.

CloudBeaver Community has no MongoDB: use DbGate for MongoDB and DocumentDB.

## Layout

| Path | |
| --- | --- |
| `modules/tools-fleet/` | Everything above, from the contract; `templates/start-tools.sh.tftpl` is the start-up script |
| `infrastructure/<environment>/` | One root per environment (one AWS account each), reading `tools/` |
| `tools/` | Pinned images, the schedule, the RDS bundle's checksum |
| `scripts/init-tools.sh` | Sets up a clone: files, GitHub Environments, and the lines core needs |
| `scripts/fetch-role-arn.sh` | Connects the repository to the roles core generates |
| `scripts/ci/start-tools.sh` | The Start tools workflow's step |

## Workflows

| Workflow | When | |
| --- | --- | --- |
| Tests | every pull request and push | shellcheck, script tests, format, lock files, validate, module tests |
| Plan | pull requests | each environment, under `<environment>-plan` |
| Deploy | merge to `main` | development, then staging, then production, each under its environment |
| Start tools | by hand | one environment, under its environment (same reviewers) |

## Checks

```bash
terraform fmt -check -recursive
(cd modules/tools-fleet && terraform init -backend=false && terraform test)
bash scripts/ci/tests/run-all.sh
shellcheck -S warning scripts/*.sh scripts/ci/*.sh
```

First setup: `docs/first-setup.md`.
