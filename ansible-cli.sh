#!/usr/bin/env bash
set -euo pipefail

#####################################
# CONFIG
#####################################
DEFAULT_GROUP="interactive"
ANSIBLE_CP_DIR="$HOME/.ansible/cp"
BECOME_OPTS=""

#####################################
# HEADER
#####################################
echo "===================================================="
echo " Ansible Interactive SSH Command Runner (Root Mode)"
echo "===================================================="
echo

#####################################
# ROOT / SU SELECTION
#####################################
read -rp "Run commands as root? (y/n): " ROOT_MODE

if [[ "$ROOT_MODE" =~ ^[Yy]$ ]]; then
  BECOME_OPTS="-b"
  read -rp "Prompt for sudo password? (y/n): " ASK_PASS
  [[ "$ASK_PASS" =~ ^[Yy]$ ]] && BECOME_OPTS="-b --ask-become-pass"
  echo "✅ Root (sudo) mode enabled"
else
  echo "✅ Running as normal user"
fi

#####################################
# INVENTORY SETUP
#####################################
echo
echo "Choose inventory source:"
echo "  1) Enter hosts manually"
echo "  2) Provide path to inventory file"
echo
read -rp "Select option (1 or 2): " INVENTORY_OPTION

HOST_LIST=()
INVENTORY=""

if [[ "$INVENTORY_OPTION" == "1" ]]; then
  echo
  echo "Enter hostnames or IPs (type 'done' to finish)"
  echo

  while true; do
    read -rp "Enter host: " HOST
    [[ "$HOST" == "done" ]] && break
    [[ -z "$HOST" ]] && continue

    HOST_LIST+=("$HOST")

    echo
    echo "✅ Hosts added so far:"
    for h in "${HOST_LIST[@]}"; do
      echo " - $h"
    done
    echo

    read -rp "Add another host? (y/n): " ADD_MORE
    [[ ! "$ADD_MORE" =~ ^[Yy]$ ]] && break
  done

  [[ "${#HOST_LIST[@]}" -eq 0 ]] && { echo "❌ No hosts entered."; exit 1; }

  INVENTORY=$(mktemp /tmp/ansible_inventory.XXXXXX)

  {
    echo "[$DEFAULT_GROUP]"
    for h in "${HOST_LIST[@]}"; do
      echo "$h"
    done
  } > "$INVENTORY"

  echo "✅ Temporary inventory created: $INVENTORY"

elif [[ "$INVENTORY_OPTION" == "2" ]]; then
  read -rp "Enter full path to inventory file: " INVENTORY
  [[ ! -f "$INVENTORY" ]] && { echo "❌ Inventory not found."; exit 1; }
  DEFAULT_GROUP="all"
  echo "✅ Using inventory: $INVENTORY"
else
  echo "❌ Invalid option."
  exit 1
fi

#####################################
# REACHABILITY CHECK
#####################################
echo
echo "Checking host reachability..."
echo "--------------------------------"

PING_OUTPUT=$(ansible "$DEFAULT_GROUP" -i "$INVENTORY" $BECOME_OPTS -m ping -o || true)

echo
echo "✅ Reachable hosts:"
echo "$PING_OUTPUT" | grep 'SUCCESS' | awk -F'|' '{print " - " $1}'

echo
echo "❌ Unreachable hosts:"
echo "$PING_OUTPUT" | grep 'UNREACHABLE' | awk -F'|' '{print " - " $1}'

#####################################
# AUTO-EXCLUDE UNREACHABLE HOSTS
#####################################
echo
read -rp "Auto-update inventory to exclude unreachable hosts? (y/n): " AUTO_UPDATE

if [[ "$AUTO_UPDATE" =~ ^[Yy]$ ]]; then
  REACHABLE_HOSTS=$(echo "$PING_OUTPUT" | grep 'SUCCESS' | awk -F'|' '{print $1}')

  [[ -z "$REACHABLE_HOSTS" ]] && { echo "❌ No reachable hosts."; exit 1; }

  FILTERED_INVENTORY=$(mktemp /tmp/ansible_inventory.reachable.XXXXXX)
  {
    echo "[reachable]"
    echo "$REACHABLE_HOSTS"
  } > "$FILTERED_INVENTORY"

  INVENTORY="$FILTERED_INVENTORY"
  DEFAULT_GROUP="reachable"

  echo "✅ Inventory updated to reachable hosts only."
fi

#####################################
# SSH WARM-UP
#####################################
echo
echo "Warming up SSH connections..."
ansible "$DEFAULT_GROUP" -i "$INVENTORY" $BECOME_OPTS -m ping >/dev/null 2>&1 || true

#####################################
# COMMAND LOOP
#####################################
echo
echo "===================================================="
echo " Enter commands to run via SSH (Ansible)"
echo " Type 'exit' or 'quit' to stop"
echo "===================================================="

while true; do
  echo
  read -rp "ansible> " CMD

  [[ "$CMD" == "exit" || "$CMD" == "quit" ]] && break
  [[ -z "$CMD" ]] && continue

  ansible "$DEFAULT_GROUP" -i "$INVENTORY" $BECOME_OPTS -a "$CMD"
done

#####################################
# CLEANUP
#####################################
echo
echo "Cleaning up SSH connections..."
pkill -f "ansible-ssh" 2>/dev/null || true
rm -f "$ANSIBLE_CP_DIR"/* 2>/dev/null || true

[[ "$INVENTORY_OPTION" == "1" ]] && rm -f "$INVENTORY"

echo "Done."