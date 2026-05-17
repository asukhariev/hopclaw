#!/usr/bin/env bash
# Start a previously stopped instance.

set -euo pipefail
. "$(dirname "$0")/config.sh"
aws_check
require_state

section "Starting $INSTANCE_ID"
aws ec2 start-instances \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'StartingInstances[0].[InstanceId,CurrentState.Name,PreviousState.Name]' \
    --output table

echo ""
echo "Waiting for running state..."
aws ec2 wait instance-running \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID"
echo ""
echo "Back up. RDP to $EIP_PUBLIC as Administrator (password unchanged from when you set it)."
