#!/usr/bin/env bash
set -euo pipefail

LAN="${LAN:-10.18.16.0/20}"
UPLINK="${UPLINK:-}"
CLIENT="${CLIENT:-}"

usage() {
  cat <<'EOF'
share-internet.sh - Turn this host into a temporary NAT gateway that shares
its internet uplink with another local network.

This host must have one interface on the network to share with and another
interface with a working internet route. Traffic from that network is
masqueraded (SNAT) out the uplink and IP forwarding is enabled.

Usage:
  share-internet.sh up   [--lan CIDR] [--uplink IFACE] [--client HOST]
  share-internet.sh down [--lan CIDR] [--uplink IFACE] [--client HOST]

  --lan     network to NAT                     (default 10.18.16.0/20, or set $LAN)
  --uplink  internet-facing interface          (default: iface of the default route)
  --client  also set/clear the default route on this host over SSH, pointing
            it at this gateway (the host should sit within --lan)

The client-side route is runtime-only and clears on reboot. iptables/sysctl
changes use sudo; the optional --client SSH runs as the invoking user.
EOF
  exit "${1:-0}"
}

[[ $# -ge 1 ]] || usage 1
case "$1" in -h | --help) usage 0 ;; esac
ACTION="$1"
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lan) LAN="$2"; shift 2 ;;
    --uplink) UPLINK="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    -h | --help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

case "$ACTION" in up | down) ;; *) echo "action must be 'up' or 'down'" >&2; usage 1 ;; esac

SUDO=""
[[ $EUID -eq 0 ]] || SUDO="sudo"

UPLINK="${UPLINK:-$(ip route show default | awk 'NR==1 {print $5}')}"
[[ -n "$UPLINK" ]] || { echo "could not determine uplink interface; pass --uplink" >&2; exit 1; }

GW_ADDR="$(ip route show "$LAN" 2>/dev/null | sed -n 's/.*src \([0-9.]\+\).*/\1/p' | head -n1)"

rule_specs() {
  printf '%s\n' \
    "nat|POSTROUTING -s $LAN -o $UPLINK -j MASQUERADE" \
    "filter|FORWARD -s $LAN -o $UPLINK -j ACCEPT" \
    "filter|FORWARD -d $LAN -i $UPLINK -m state --state RELATED,ESTABLISHED -j ACCEPT"
}

if [[ "$ACTION" == up ]]; then
  $SUDO sysctl -qw net.ipv4.ip_forward=1
  while IFS='|' read -r table rest; do
    # shellcheck disable=SC2086
    $SUDO iptables -t "$table" -C $rest 2>/dev/null || $SUDO iptables -t "$table" -A $rest
  done < <(rule_specs)
  echo "NAT up: $LAN -> $UPLINK (gateway $GW_ADDR)"
else
  while IFS='|' read -r table rest; do
    # shellcheck disable=SC2086
    while $SUDO iptables -t "$table" -C $rest 2>/dev/null; do $SUDO iptables -t "$table" -D $rest; done
  done < <(rule_specs)
  echo "NAT down: removed rules for $LAN -> $UPLINK"
fi

if [[ -n "$CLIENT" ]]; then
  if [[ "$ACTION" == up ]]; then
    ssh "$CLIENT" -- sudo ip route replace default via "$GW_ADDR"
    echo "Set default route on $CLIENT via $GW_ADDR"
  else
    ssh "$CLIENT" -- sudo ip route del default via "$GW_ADDR" || true
    echo "Cleared default route on $CLIENT"
  fi
elif [[ "$ACTION" == up ]]; then
  echo "Point each client's default route at this gateway. On a client run:"
  echo "    sudo ip route replace default via $GW_ADDR"
fi
