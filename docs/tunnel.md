# Production: the tunnel

Production's tools have no web address. Reach them through a Session Manager port-forwarding tunnel, with your AWS sign-in.

**You need:** the AWS CLI, the Session Manager plugin, and an AWS sign-in to the production account that may start a session on the tools server (IAM Identity Center; an administrator can too).

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
