# First setup

1. **Initialise the clone:**
   `scripts/init-tools.sh --project <project> --region <region> --environments <list> --reviewers <login,...>`
   `--environments` is the environments the tools run in (any of development, staging, production, only ones core runs; omitted, `.github/environments.json` is kept). It writes those environments' tfvars and backend, creates their GitHub Environments (each and its `-plan`), and prints three lines and the lock commands.
2. **In core**, add those lines to the `terraform.tfvars` of each of those environments and let core apply them. Core then generates this repository's role in each account and publishes its ARN.
3. **Connect the roles:** `scripts/fetch-role-arn.sh --core <owner>/<core-repository>` (or `--environment <one>` as each is applied).
4. **Lock the providers for every platform** in each environment, then commit the lock files (a plain `terraform init` writes only your own platform's hashes, and CI refuses that):
   `terraform -chdir=infrastructure/<environment> init -backend=false`, then `terraform -chdir=infrastructure/<environment> providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64`
5. **Commit and open a pull request.** Plan shows each environment listed; merging deploys them in order.
6. **First start:** run **Start tools** for development, then open `https://dbgate.<domain>`. Sign in with the invitation Cognito emailed you (you must be an agent of a service, or on core's platform list), then connect with your own database login.

If the provider version changes, regenerate each environment's lock file for every platform and commit it (CI requires at least four `h1:` hashes per provider):
`terraform -chdir=infrastructure/<environment> providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64`
