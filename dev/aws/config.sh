#!/usr/bin/env bash
# HopClaw EC2 — shared config for the lifecycle scripts.
# Source me from each script: . "$(dirname "$0")/config.sh"

# AWS profile to use (run `aws configure --profile hopclaw` if you don't have it yet).
export AWS_PROFILE="${AWS_PROFILE:-hopclaw}"

# Region — eu-central-1 (Frankfurt) is the lowest-latency major AWS region from Ukraine.
# Alternatives: eu-west-1 (Ireland), eu-north-1 (Stockholm).
export AWS_REGION="${AWS_REGION:-eu-central-1}"

# Resource naming — every resource gets tagged with this so we can find / destroy them as a unit.
export PROJECT_TAG="hopclaw"
export NAME_PREFIX="hopclaw-win"

# Instance sizing.
# t3.large = 2 vCPU / 8 GB RAM, ~$0.10/hr Linux + ~$0.046/hr Windows license = ~$0.15/hr running.
# Stopped: only EBS billed (~$5/mo for 50 GB gp3).
export INSTANCE_TYPE="t3.large"
export EBS_SIZE_GB="50"

# Your current public IP, used to lock RDP to just your machine.
# Auto-detected if not set; pin manually if you want a specific CIDR.
export ALLOWED_RDP_CIDR="${ALLOWED_RDP_CIDR:-$(curl -s https://checkip.amazonaws.com)/32}"

# Local key pair location — Terraform/AWS uses this to encrypt the Windows Administrator password.
export KEY_NAME="${NAME_PREFIX}-key"
export KEY_DIR="${HOME}/.ssh"
export KEY_PATH="${KEY_DIR}/${KEY_NAME}.pem"

# Security group name.
export SG_NAME="${NAME_PREFIX}-sg"

# Cached state file — the create script writes here so other scripts can find what was made.
export STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.aws-state.env"

# Helpers --------------------------------------------------------------------
load_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck source=/dev/null
        . "$STATE_FILE"
    fi
}

require_state() {
    load_state
    if [ -z "${INSTANCE_ID:-}" ]; then
        echo "ERROR: no instance recorded in $STATE_FILE — run 01-create.sh first." >&2
        exit 1
    fi
}

aws_check() {
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        echo "ERROR: AWS credentials for profile '$AWS_PROFILE' don't work." >&2
        echo "Fix: aws configure --profile $AWS_PROFILE" >&2
        exit 1
    fi
}

section() {
    echo ""
    echo "===== $* ====="
}
