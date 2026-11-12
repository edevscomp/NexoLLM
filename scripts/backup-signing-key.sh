#!/bin/bash
# Saves an encrypted copy of the release signing key, protected by a password you choose.
# Keep the file on a USB stick or in a password manager, and the password somewhere else.
# Without the key (Keychain or this backup) no future update can be verified by installed copies.
#
#   scripts/backup-signing-key.sh [output-file]      default: ~/Desktop/NexoLLM-signing-key.backup
#   restore:  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in <file> | \
#             xargs -I{} security add-generic-password -s "NexoLLM Release Signing" -a ed25519 -w {}
set -euo pipefail
OUT="${1:-$HOME/Desktop/NexoLLM-signing-key.backup}"
KEY="$(security find-generic-password -s "NexoLLM Release Signing" -a ed25519 -w)"
umask 077
echo "Choose a strong password for the backup (you'll type it twice):"
printf '%s' "$KEY" | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -out "$OUT"
unset KEY
echo "Encrypted backup written to $OUT"
