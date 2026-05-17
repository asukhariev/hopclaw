#!/usr/bin/env bash
# Nuke everything — instance, EIP, security group, key pair, local .pem.
# Stops all billing. Use when Phase 0 is done and we've moved to a physical box at HOP Studio.

set -euo pipefail
. "$(dirname "$0")/config.sh"
aws_check
require_state

section "DESTROY confirmation"
echo "About to delete:"
echo "  Instance       : $INSTANCE_ID"
echo "  Elastic IP     : $EIP_PUBLIC ($EIP_ALLOC)"
echo "  Security group : $SG_ID"
echo "  Key pair (AWS) : $KEY_NAME"
echo "  Key pair (local): $KEY_PATH"
echo ""
read -r -p "Type 'destroy' to confirm: " confirm
if [ "$confirm" != "destroy" ]; then
    echo "Aborted."
    exit 0
fi

section "Terminating instance"
aws ec2 terminate-instances \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" >/dev/null
echo "Waiting for terminated state..."
aws ec2 wait instance-terminated \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID"
echo "Done."

section "Releasing Elastic IP"
aws ec2 release-address \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --allocation-id "$EIP_ALLOC" || true
echo "Done."

section "Deleting security group"
aws ec2 delete-security-group \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --group-id "$SG_ID" || true
echo "Done."

section "Deleting key pair"
aws ec2 delete-key-pair \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --key-name "$KEY_NAME" || true
rm -f "$KEY_PATH"
echo "Done."

section "Clearing state file"
rm -f "$STATE_FILE"

echo ""
echo "All HopClaw AWS resources are gone. Billing for this stack should be \$0 within 24h."
