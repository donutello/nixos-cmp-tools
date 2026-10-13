# Copyright (C) 2026 donutello, Wh1stle05 and jdowning100. GPL-2.0-only.
# Hand every CMP 90HX from the stock nvidia module to the patched one (compute
# unlock), then open two privilege masks and retrain the link (PCIe Gen2).
# The reload protocol is jdowning100/cmpunlocker's, as Wh1stle05/cmp90hx cut it
# down to two masks; ported from the latter. Expects MODULES, MASKREAD and
# CMP90_PCIE_GEN2 in the environment.
set +e

spec=/var/lib/cmpunlocker-rs/rejoin16-next-write.bin # path compiled into the patched module
mask_feat=0x00823800
mask_xve=0x00088fe8
sel0=0x0082381c # compute issue-rate selectors
sel1=0x00823820
mask_tries=6
stack=(nvidia_drm nvidia_modeset nvidia_uvm nvidia_peermem nvidia)

log() { echo "cmp90hx-unlock: $*"; }
reg() { python3 "$MASKREAD" "$1" "$2" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{8}' | head -1; }
gpu_ok() { nvidia-smi -L >/dev/null 2>&1; }

unload_stack() { modprobe -r "${stack[@]}" 2>/dev/null || { sleep 2; modprobe -r "${stack[@]}" 2>/dev/null; }; }

load_patched() {
  modprobe ecc 2>/dev/null
  insmod "$MODULES/nvidia.ko" 2>/dev/null
  local _
  for _ in $(seq 30); do gpu_ok && return 0; sleep 2; done
  return 1
}

patched_loaded() {
  [[ "$(modinfo -F srcversion "$MODULES/nvidia.ko")" == "$(cat /sys/module/nvidia/srcversion 2>/dev/null)" ]]
}

# The patched module performs one queued register write per load, and only
# when it finds the selectors locked (zero). Selectors must be re-locked while
# the driver is still up: once unloaded, BAR0 is unreachable.
cycle_write() {
  local bdf=$1 addr=$2 _
  python3 -c 'import struct,sys; open(sys.argv[3],"wb").write(struct.pack("<II",int(sys.argv[1],0),int(sys.argv[2],0)))' \
    "$addr" 0xffffffff "$spec"
  for _ in 1 2 3; do
    bar0poke "$bdf" wr "$sel0" 0x0 >/dev/null 2>&1
    bar0poke "$bdf" wr "$sel1" 0x0 >/dev/null 2>&1
    [[ "$(reg "$bdf" "$sel0")$(reg "$bdf" "$sel1")" == 0x000000000x00000000 ]] && break
  done
  if [[ "$(reg "$bdf" "$sel0")" != 0x00000000 ]] || ! unload_stack; then
    log "$bdf: cannot relock selectors or unload the nvidia stack (is something holding /dev/nvidia*?)"
    bar0poke "$bdf" wr "$sel0" 0x88888888 >/dev/null 2>&1
    bar0poke "$bdf" wr "$sel1" 0x00000008 >/dev/null 2>&1
    return 1
  fi
  sleep 1
  load_patched || log "$bdf: GPU did not come back after reload"
}

open_mask() {
  local bdf=$1 addr=$2 try
  for ((try = 1; try <= mask_tries; try++)); do
    [[ "$(reg "$bdf" "$addr")" == 0xffffffff ]] && { log "$bdf: $addr open"; return 0; }
    cycle_write "$bdf" "$addr" || return 1
  done
  [[ "$(reg "$bdf" "$addr")" == 0xffffffff ]] || { log "$bdf: failed to open $addr"; return 1; }
}

retrain() {
  local bdf=$1 bridge
  bridge=$(basename "$(readlink -f "/sys/bus/pci/devices/$bdf/..")")
  setpci -s "$bridge" CAP_EXP+30.w=0002:000f # Target Link Speed := Gen2
  setpci -s "$bdf" CAP_EXP+30.w=0002:000f
  setpci -s "$bridge" CAP_EXP+10.w=0020:0020 # Retrain Link
  sleep 2
}

cards=()
for d in /sys/bus/pci/devices/*; do
  [[ "$(cat "$d/vendor" "$d/device" "$d/subsystem_device" 2>/dev/null | tr '\n' :)" == 0x10de:0x220d:0x1555: ]] || continue
  if [[ "$(basename "$(readlink -f "$d/driver")")" == nouveau ]]; then
    log "${d##*/}: bound to nouveau; set driver_override=nvidia before nouveau loads"
    continue
  fi
  cards+=("${d##*/}")
done
((${#cards[@]})) || { log "no CMP 90HX found"; exit 0; }

rm -f "$spec"
mkdir -p "$(dirname "$spec")"

if patched_loaded && gpu_ok; then
  log "patched module already loaded"
else
  unload_stack
  sleep 1
  load_patched || { log "GPU did not come up on the patched module"; exit 1; }
  log "patched module loaded"
fi

if [[ "${CMP90_PCIE_GEN2:-1}" == 1 ]]; then
  for bdf in "${cards[@]}"; do
    if [[ -z "$(reg "$bdf" "$mask_feat")" ]]; then
      log "$bdf: cannot read BAR0; iomem=relaxed must be on the kernel command line"
      continue
    fi
    open_mask "$bdf" "$mask_feat"
    open_mask "$bdf" "$mask_xve"
    retrain "$bdf"
    log "$bdf: link $(<"/sys/bus/pci/devices/$bdf/current_link_speed") x$(<"/sys/bus/pci/devices/$bdf/current_link_width")"
  done
fi

modprobe nvidia_uvm
log "done"
