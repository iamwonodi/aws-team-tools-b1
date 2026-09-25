# Decisions

| Decision | Why |
| --- | --- |
| DbGate and CloudBeaver Community, side by side | DbGate covers all three engines and visualises well; CloudBeaver adds more for PostgreSQL and MySQL. Community editions only |
| One disposable spot server per environment, on a schedule, with a Start button and a two-hour auto-off | The tools are used in working hours: spot and a schedule cost a few dollars a month. Nothing on the server needs keeping; queries saved inside a tool are lost at each stop |
| Servers of their own, in the private subnets, wearing core's team-tools group | Not customer-facing: a problem in one must not reach the customer fleets. The databases admit the team-tools group, not the fleets' |
| Images pulled from Docker Hub at each start, pinned by tag | Chosen over mirroring into ECR: simpler, at the cost of depending on Docker Hub when a server starts |
| Core's golden image plus a start-up script, not an image of its own | One hardened base for everything; the script is small and rewritten on every start |
| Schedules, Start and auto-off are Auto Scaling scheduled actions | No code to run or pay for. Start books a one-off stop only when two hours would not reach the schedule, whose own stop then applies |
| Web addresses behind core's Cognito front door in development and staging; a Session Manager tunnel in production | Production's data is reached with an AWS sign-in only, never from a web address |
| Connections prepared from the contract; each person types their own database login | Actions are traceable to a person; no password is stored |
| The RDS bundle is downloaded at start and refused unless its SHA-256 matches `tools/rds-bundle.sha256` | It is too large for user data (16 KB); the checksum makes a tampered download fail the start |
| DocumentDB's `retryWrites=false` is passed in DbGate's port field | DbGate passes no driver options but pastes the port into the connection string; DocumentDB refuses retryable writes |
| CloudBeaver's administrator is random per start, root-only | Without one its setup page makes the first visitor the administrator; connections are prepared, so nobody needs it day to day |
| Target groups get AWS-generated names from a prefix | A name is at most 32 characters, which a long project name would exceed; core scopes target groups by tag |
