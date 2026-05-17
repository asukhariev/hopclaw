# HopClaw AWS EC2 lifecycle

A handful of bash scripts that drive an AWS-CLI-only flow to spin up, connect to, pause, resume, and tear down a Windows EC2 instance for HopClaw development.

**No Terraform required** — just AWS CLI v2 (already installed) and AWS credentials.

## Files

| File | What it does |
| --- | --- |
| `config.sh` | Shared variables (region, instance type, names) + helpers. Sourced by every script. |
| `01-create.sh` | Provisions: key pair, security group, EC2 instance, Elastic IP. Idempotent. |
| `02-connect.sh` | Fetches the Windows Administrator password, copies it to clipboard, writes `hopclaw-win.rdp`. |
| `03-stop.sh` | Stops the instance (EBS preserved, compute billing stops). |
| `04-start.sh` | Starts a stopped instance. Same IP, same state. |
| `99-destroy.sh` | Nukes everything. Stops all billing. Requires typing `destroy` to confirm. |
| `.aws-state.env` | Auto-written by `01-create.sh`; read by the others. Don't edit by hand. |

## One-time setup (you, on your Mac)

```bash
# 1. Create an IAM user with EC2 + VPC permissions, generate access keys, then:
aws configure --profile hopclaw
# Paste access key ID + secret. For region enter: eu-central-1. Output: json.

# 2. Verify
aws sts get-caller-identity --profile hopclaw
# Should print Account, UserId, Arn.

# 3. Make scripts executable
chmod +x ~/Documents/Claude/Projects/HOPLAB/hopclaw/dev/aws/*.sh
```

## Spinning up (first time)

```bash
cd ~/Documents/Claude/Projects/HOPLAB/hopclaw/dev/aws
./01-create.sh
# ~3-5 minutes. Output ends with the Public IP and a "next steps" hint.

# Wait ~4 minutes for Windows to finish generating the Admin password, then:
./02-connect.sh
# Prints the password (also copies to clipboard) and writes hopclaw-win.rdp.
# Double-click the .rdp file to connect. Mac needs Microsoft Remote Desktop (free, App Store).
```

## Daily ops

```bash
# Done for the day — stop the box, save ~$95/mo:
./03-stop.sh

# Ready to work again:
./04-start.sh
# Re-run ./02-connect.sh if you forgot the password (it doesn't change across stop/start).
```

## Cost model

| State | Hourly | Monthly (if held continuously) |
| --- | --- | --- |
| Running | ~$0.15/hr (compute) + ~$0.007/hr (EBS) | ~$110/mo |
| Stopped | $0 compute + ~$0.007/hr (EBS) | ~$5/mo |
| Terminated | $0 | $0 |

**Realistic monthly bill** for Phase 0 (running ~6 hrs/day, stopped overnight + weekends): **$25–40/mo**.

## When Phase 0 is done

```bash
./99-destroy.sh
# Type 'destroy' to confirm. Billing goes to zero within 24h.
```

We'll move HopClaw to a physical Windows box at HOP Studio for v1 — at that point the AWS dev VM has served its purpose.

## Defaults you can override

Edit `config.sh` or set env vars before running:

```bash
export AWS_REGION=eu-west-1     # use Ireland instead of Frankfurt
export INSTANCE_TYPE=t3.xlarge  # bump to 4 vCPU / 16 GB
export ALLOWED_RDP_CIDR=1.2.3.4/32  # pin to a specific IP instead of auto-detect
./01-create.sh
```
