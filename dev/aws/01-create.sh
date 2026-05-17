#!/usr/bin/env bash
# Create the EC2 Windows VM for HopClaw.
# Idempotent: re-running won't duplicate resources — it picks up what's already there.

set -euo pipefail
. "$(dirname "$0")/config.sh"
aws_check

section "1. Find latest Windows Server 2022 Base AMI in $AWS_REGION"
AMI_ID=$(aws ec2 describe-images \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --owners amazon \
    --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
echo "AMI_ID=$AMI_ID"

section "2. Ensure key pair exists ($KEY_NAME)"
mkdir -p "$KEY_DIR"
if [ -f "$KEY_PATH" ] && aws ec2 describe-key-pairs --profile "$AWS_PROFILE" --region "$AWS_REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo "Key pair already exists in AWS and locally at $KEY_PATH"
else
    if aws ec2 describe-key-pairs --profile "$AWS_PROFILE" --region "$AWS_REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
        echo "WARNING: AWS has key pair '$KEY_NAME' but local $KEY_PATH is missing."
        echo "Either restore the .pem file from backup, or delete the AWS key with:"
        echo "  aws ec2 delete-key-pair --profile $AWS_PROFILE --region $AWS_REGION --key-name $KEY_NAME"
        echo "and re-run this script. Aborting."
        exit 1
    fi
    aws ec2 create-key-pair \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    echo "Created key pair and saved private key to $KEY_PATH"
fi

section "3. Look up default VPC"
VPC_ID=$(aws ec2 describe-vpcs \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "ERROR: No default VPC in $AWS_REGION. Either create one or modify this script for a specific VPC."
    exit 1
fi
echo "VPC_ID=$VPC_ID"

section "4. Ensure security group ($SG_NAME) exists with RDP from $ALLOWED_RDP_CIDR"
SG_ID=$(aws ec2 describe-security-groups \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")
if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 create-security-group \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --group-name "$SG_NAME" \
        --description "HopClaw Windows dev VM - RDP only" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)
    aws ec2 create-tags --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --resources "$SG_ID" \
        --tags "Key=Project,Value=$PROJECT_TAG"
    echo "Created security group: $SG_ID"
else
    echo "Security group already exists: $SG_ID"
fi

# Add RDP rule if missing (idempotent — ignores "already exists" errors)
aws ec2 authorize-security-group-ingress \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 3389 \
    --cidr "$ALLOWED_RDP_CIDR" 2>/dev/null || echo "RDP rule for $ALLOWED_RDP_CIDR already exists (or just added)"

# Add Tailscale UDP for later (mesh networking — won't open any inbound by itself, but allows the daemon to talk)
aws ec2 authorize-security-group-ingress \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --group-id "$SG_ID" \
    --protocol udp --port 41641 \
    --cidr "0.0.0.0/0" 2>/dev/null || echo "Tailscale UDP rule already exists (or just added)"

section "5. Launch (or find existing) EC2 instance"
EXISTING=$(aws ec2 describe-instances \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" "Name=tag:Name,Values=$NAME_PREFIX" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "None")
if [ "$EXISTING" != "None" ] && [ -n "$EXISTING" ]; then
    INSTANCE_ID="$EXISTING"
    echo "Instance already exists: $INSTANCE_ID"
else
    INSTANCE_ID=$(aws ec2 run-instances \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$EBS_SIZE_GB,VolumeType=gp3,DeleteOnTermination=true}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_PREFIX},{Key=Project,Value=$PROJECT_TAG}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    echo "Launched instance: $INSTANCE_ID"
fi

section "6. Allocate / attach Elastic IP"
EIP_ALLOC=$(aws ec2 describe-addresses \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=tag:Project,Values=$PROJECT_TAG" \
    --query 'Addresses[0].AllocationId' \
    --output text 2>/dev/null || echo "None")
if [ "$EIP_ALLOC" = "None" ] || [ -z "$EIP_ALLOC" ]; then
    EIP_RESULT=$(aws ec2 allocate-address \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
        --query '[AllocationId,PublicIp]' \
        --output text)
    EIP_ALLOC=$(echo "$EIP_RESULT" | cut -f1)
    EIP_PUBLIC=$(echo "$EIP_RESULT" | cut -f2)
    echo "Allocated Elastic IP: $EIP_PUBLIC ($EIP_ALLOC)"
else
    EIP_PUBLIC=$(aws ec2 describe-addresses \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --allocation-ids "$EIP_ALLOC" \
        --query 'Addresses[0].PublicIp' \
        --output text)
    echo "Elastic IP already exists: $EIP_PUBLIC ($EIP_ALLOC)"
fi

# Wait for instance to be running before associating EIP
echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID"

aws ec2 associate-address \
    --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-id "$INSTANCE_ID" \
    --allocation-id "$EIP_ALLOC" >/dev/null
echo "Associated $EIP_PUBLIC -> $INSTANCE_ID"

section "7. Save state for other scripts"
cat > "$STATE_FILE" <<EOF
# Auto-generated by 01-create.sh — do not edit
INSTANCE_ID="$INSTANCE_ID"
EIP_ALLOC="$EIP_ALLOC"
EIP_PUBLIC="$EIP_PUBLIC"
SG_ID="$SG_ID"
AMI_ID="$AMI_ID"
EOF
echo "State written to $STATE_FILE"

section "Done — next steps"
echo ""
echo "  Public IP   : $EIP_PUBLIC"
echo "  Instance    : $INSTANCE_ID"
echo "  Private key : $KEY_PATH"
echo ""
echo "  Windows is still booting + generating the Administrator password (~4 min)."
echo "  Run ./02-connect.sh once it's ready to get the RDP credentials."
