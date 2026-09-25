# Production: the tunnel

Production's tools have no web address. Reach them through a Session Manager port-forwarding tunnel, with your AWS sign-in.

**You need:** the AWS CLI, the Session Manager plugin, and a tunnel sign-in: you are listed for production in the identity repository (`aws-identity-b1`), which gives you the `TeamToolsTunnel` permission set in the production account. It can open a port-forwarding tunnel to the tools' server and nothing else.

**Once, set up your sign-in** (you will need the access portal address, from whoever runs the identity repository):
```bash
aws configure sso --profile tools-production
# SSO start URL:  the access portal address
# SSO region:     the Region of IAM Identity Center
# then choose the production account and the TeamToolsTunnel role
```

**Each time:**

0. Sign in: `aws sso login --profile tools-production`, and add `--profile tools-production` to the commands below.
1. Start the tools if they are off: the **Start tools** workflow, production.
2. Find the server:
   ```bash
   aws ec2 describe-instances --region <region> \
     --filters "Name=tag:Service,Values=team-tools" "Name=instance-state-name,Values=running" \
     --query 'Reservations[].Instances[].InstanceId' --output text
   ```
3. Open the tunnel, one per tool:
   ```bash
   aws ssm start-session --region <region> --target <instance-id> \
     --document-name AWS-StartPortForwardingSession \
     --parameters portNumber=3000,localPortNumber=3000     # DbGate
   # CloudBeaver: portNumber=8978,localPortNumber=8978
   ```
4. Open `http://localhost:3000` (or `:8978`) and connect with your own database login. Production is read-only unless core has approved write for your login.
