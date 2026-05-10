 DevOps Sandbx Platform

A self-service ephemeral environment platform where users can spin up isolated environments, deploy apps, simulate failures, monitor health, and destroy everything automatically.

Built with: Docker, Docker Compose, Nginx, Bash, Python

 Architecture
                 +----------------------+
                 |   GitHub Actions     |
                 | (CI/CD Pipeline)     |
                 +----------+-----------+
                            |
                            v
                 +----------------------+
                 |  Sandbox API (Flask) |
                 +----------+-----------+
                            |
        +-------------------+-------------------+
        |                                       |
        v                                       v
+---------------+                     +------------------+
| Env Manager   |                     | Monitoring Agent |
| (Bash Scripts)|                     | (Health checks)  |
+-------+-------+                     +--------+---------+
        |                                      |
        v                                      v
+-------------------+            +---------------------------+
| Docker Containers |            | Metrics / Logs / Alerts   |
| (Isolated envs)   |            | Slack / JSON endpoints    |
+-------------------+            +---------------------------+
        |
        v
+-------------------+
| Nginx Reverse Proxy|
| (Per-env routing)  |
+-------------------+
⚙️ Prerequisites
Docker + Docker Compose
Python 3.10+
Bash shell
Make (optional but recommended)
Linux server (Ubuntu recommended)
 Quick Start (5 commands)
git clone <your-repo-url>
cd devops-sandbox

make build
make up
make status
 Full Demo Workflow
1. Create environment
./platform/create_env.sh user1
2. Deploy sample app
./platform/deploy.sh user1 sample-app
3. Check health
curl http://localhost:5000/health/user1
4. Simulate outage (Chaos mode)
./platform/simulate_outage.sh user1


stop container
spike CPU
break service intentionally
5. Observe system behavior
curl http://localhost:5000/metrics

Check:

uptime drops
request errors increase
alerts triggered
6. Recover system
./platform/recover.sh user1
7. Destroy environment
./platform/destroy_env.sh user1
 Features
 Isolated Docker environments per user
⚙Auto-provisioning via scripts
 Health monitoring API
 Chaos engineering simulation
 Alert system (logs / webhook ready)
 Auto-recovery workflows
 Auto-cleanup of expired environments
