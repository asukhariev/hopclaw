#!/usr/bin/env bash
# Stop the instance to save on compute costs.
# EBS storage keeps billing (~$5/mo) but compute (~$0.15/hr) stops.
# State (installed software, files) is preserved — start back up exactly where you left off.

set -euo pipefail
. "$(dirname "$0")/config.sh"
aws_check
require_state

section "Stopping $INSTANCE_ID"
aws ec2 stop-instances \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'StoppingInstances[0].[InstanceId,CurrentState.Name,PreviousState.Name]' \
    --output table

echo ""
echo "Stopped (or stopping). EBS keeps your data, Elastic IP stays attached."
echo "Run ./04-start.sh to bring it back up — same IP, same state."
