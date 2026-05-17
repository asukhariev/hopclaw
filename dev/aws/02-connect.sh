#!/usr/bin/env bash
# Fetch the Windows Administrator password and print RDP details.
# Run after 01-create.sh — Windows takes ~4 minutes to generate the password.

set -euo pipefail
. "$(dirname "$0")/config.sh"
aws_check
require_state

section "Fetching encrypted password for $INSTANCE_ID"
PASSWORD=""
for attempt in 1 2 3 4 5 6 7 8; do
    PASSWORD=$(aws ec2 get-password-data \
        --profile "$AWS_PROFILE" --region "$AWS_REGION" \
        --instance-id "$INSTANCE_ID" \
        --priv-launch-key "$KEY_PATH" \
        --query 'PasswordData' \
        --output text 2>/dev/null || echo "")
    if [ -n "$PASSWORD" ] && [ "$PASSWORD" != "None" ]; then
        break
    fi
    echo "Password not ready yet (attempt $attempt/8) — waiting 30s..."
    sleep 30
done

if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "None" ]; then
    echo ""
    echo "ERROR: password still not available after 4 minutes."
    echo "AWS sometimes takes longer — wait a few more minutes and re-run."
    exit 1
fi

section "RDP connection details"
echo ""
echo "  Host     : $EIP_PUBLIC"
echo "  User     : Administrator"
echo "  Password : $PASSWORD"
echo ""
echo "  (Copied to your clipboard.)"
echo ""

# Copy password to clipboard for quick paste into RDP client
printf '%s' "$PASSWORD" | pbcopy

# Write an .rdp file the user can double-click
RDP_FILE="$(dirname "$0")/hopclaw-win.rdp"
cat > "$RDP_FILE" <<EOF
full address:s:$EIP_PUBLIC
username:s:Administrator
screen mode id:i:2
desktopwidth:i:1920
desktopheight:i:1080
session bpp:i:32
audiomode:i:2
redirectclipboard:i:1
redirectprinters:i:0
EOF
echo "  Saved RDP file: $RDP_FILE"
echo "  Double-click to open in Microsoft Remote Desktop (paste password when prompted)."
echo ""
echo "  If Microsoft Remote Desktop isn't installed, get it free from the Mac App Store:"
echo "  https://apps.apple.com/app/microsoft-remote-desktop/id1295203466"
