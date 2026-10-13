# nixos-cmp-tools

NixOS modules that unlock NVIDIA CMP 170HX and CMP 90HX mining cards and lower the 90HX's idle power draw.

```nix
{
  inputs.cmp-tools.url = "github:donutello/nixos-cmp-tools/nixos-26.05";

  outputs = { nixpkgs, cmp-tools, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        cmp-tools.nixosModules.default
        {
          hardware.nvidia.cmpTools.cmp90hx.enable = true;
          hardware.nvidia.cmpTools.idlePower.enable = true;
        }
      ];
    };
  };
}
```

Each NixOS stable release has a branch, `nixos-YY.MM`, holding what has passed on real cards on that release; follow the one named like your nixpkgs. The driver is built from your nixpkgs' kernel, so a branch is only tested on its own release, and the modules warn when the host runs another. Once the next release is out, the older branch stops changing but stays as it was last tested.

Requirements: the NixOS release the branch is named after, x86_64, `hardware.nvidia.open = true`, **Secure Boot off** (the patched modules are unsigned). A host takes one of the two unlocks, not both: they need different driver versions.

**No cold boot** is needed for either card; both unlocks are redone on every boot. A plain reboot from the stock driver was checked on both: the 90HX came up unlocked, and every register the 170HX's ECC patch writes read back as written. A driver update reaches the card at the next boot, and switching into one that changes the driver version leaves the new userspace driver talking to the old kernel module, so CUDA fails until that boot. Apply those with `nixos-rebuild boot` and a reboot. `hardware.nvidia.cmpTools.kernelModules`, which the card modules set, names the modules the card runs, so comparing it between the booted and the newest generation shows whether a reboot is still due.

All numbers below: one card in a PCIe x16 slot, case fans at 100 %, stock power limit. Stock is the same nvidia-open version, unpatched. Measured with CUDA:

- GEMM: cuBLAS `cublasGemmEx`, 8192 × 8192, median over 30 s; fp16 and bf16 accumulate in fp32, int8 in int32.
- FMA: chains of fused multiply-adds, the peak `clpeak`-style tools report.
- Sustained: the bf16 GEMM for 10 minutes, median of the last minute.
- Memory: a read kernel over device memory. PCIe: pinned 256 MiB copies, host to device / device to host.
- Idle: the 60 s mean of `nvidia-smi power.draw` with nothing running.

## CMP 170HX

`10de:20c2` (8 GB) and `10de:2082` (10 GB).

| Option | Default | Effect |
|---|---|---|
| `hardware.nvidia.cmpTools.cmp170hx.enable` | `false` | Patched nvidia-open, of the version `pkgs/sources.json` pins, as `hardware.nvidia.package`. |

The patched driver unlocks the card on every load; there is no service. It also sets the registers that turn on ECC for the HBM and on-chip memories, which the cards ship with off.

Measured on 615.71.09 with ECC on, `10de:20c2`; two cards, within 1 % of each other:

| | Stock | Unlocked |
|---|---|---|
| Memory | 8 GB | 64 GB |
| SMs | 70 | 74 |
| bf16 GEMM | 6.4 TFLOPS | 192 TFLOPS |
| bf16, sustained | 6.4 TFLOPS at 77 W | 191 TFLOPS at the 300 W limit |
| fp16 GEMM | 6.5 TFLOPS | 164 TFLOPS |
| tf32 GEMM | 3.2 TFLOPS | 94 TFLOPS |
| int8 GEMM | 13 TOPS | 255 TOPS |
| fp64 GEMM | 0.20 TFLOPS | 13.2 TFLOPS |
| FP32 FMA | 410 GFLOPS | 13,833 GFLOPS |
| FP64 FMA | 197 GFLOPS | 6,944 GFLOPS |
| Memory read | 1,670 GB/s | 1,675 GB/s |
| PCIe | Gen1, 3.2 / 3.3 GB/s | Gen2, 6.2 / 6.7 GB/s |
| Idle | P0, 33 W | P0, 34 W |

## CMP 90HX

`10de:220d`, subsystem `10de:1555`.

| Option | Default | Effect |
|---|---|---|
| `hardware.nvidia.cmpTools.cmp90hx.enable` | `false` | Stock nvidia-open, of the version `pkgs/sources.json` pins; `cmp90hx-unlock.service` then reloads the card on patched modules. |
| `hardware.nvidia.cmpTools.cmp90hx.pcieGen2.enable` | `true` | Also opens PCIe Gen2: two more reloads and a link retrain. Adds `iomem=relaxed`. |

The patched driver cannot be the first one to start the card after boot, hence the service. It takes about a minute, and nothing that opens `/dev/nvidia*` may start before it finishes. On a host that also uses nouveau, set `driver_override=nvidia` on the 90HX before nouveau loads.

Measured on 610.43.03 with `pcieGen2`:

| | Stock | Unlocked |
|---|---|---|
| Memory | 10 GB | 10 GB |
| SMs | 50 | 50 |
| bf16 GEMM | 3.0 TFLOPS | 54.4 TFLOPS |
| bf16, sustained | 3.0 TFLOPS at 127 W | 54.2 TFLOPS at the 250 W limit |
| fp16 GEMM | 3.0 TFLOPS | 68.8 TFLOPS |
| tf32 GEMM | 1.5 TFLOPS | 36.2 TFLOPS |
| int8 GEMM | 6.0 TOPS | 134 TOPS |
| FP32 FMA | 667 GFLOPS | 22,816 GFLOPS |
| FP64 FMA | 316 GFLOPS | 313 GFLOPS |
| Memory read | 741 GB/s | 741 GB/s |
| PCIe | Gen1, 3.1 / 3.4 GB/s | Gen2, 6.3 / 6.7 GB/s |
| Idle | P0, 88 W | P0, 81 W; P8, 13 W with `idlePower` |

FP64 stays at the GA102 chip's own rate, and the memory runs at full speed even on stock.

## Idle power

| Option | Default | Effect |
|---|---|---|
| `hardware.nvidia.cmpTools.idlePower.enable` | `false` | Runs [nvidia-pstated](https://github.com/sasha0552/nvidia-pstated): P8 when idle, full clocks on load. Needs the unfree `cuda_nvml_dev` allowed. |
| `hardware.nvidia.cmpTools.idlePower.idleSeconds` | `30` | Idle time before dropping to P8. |

Worth it on the 90HX (81 W → 13 W). The 170HX already idles at its lowest clock and pstated does not lower it further.

## Credits and licence

Copyright © 2026 donutello. GPL-2.0-only (`LICENSE`), a licence the kernel modules it patches are offered under and the one most upstreams below use. The 170HX Gen2 patch and the 90HX unlock script derive from upstream code; their headers name its authors.

It fetches, and does not vendor, the work it builds on; the upstreams below and the artefacts built from them keep their own licences:

| Upstream | Licence | Used for |
|---|---|---|
| [amoghmunikote/cmpunlocker](https://github.com/amoghmunikote/cmpunlocker) | GPL-2.0 | The 170HX patch series. Upstream credits [asm64-hooligan](https://github.com/asm64-hooligan) for the 64 GB BAR1, [lesj0610](https://github.com/lesj0610) for the GPU-profiling unlock (the SKU mask) and [armand0e](https://github.com/armand0e) for the late-PMA fix |
| [pearlfortune/cmpunlocker](https://github.com/pearlfortune/cmpunlocker) | MIT (`LICENSE` in the release bundle) | 90HX patches 0014 and 0015, from its stockflow release bundle; a separate tool from amoghmunikote's despite the name |
| [jdowning100/cmpunlocker](https://github.com/jdowning100/cmpunlocker) | GPL-2.0 | 90HX patch 0016 (PCIe Gen2), `bar0poke`, and the reload protocol that opens the privilege masks |
| [Wh1stle05/cmp90hx](https://github.com/Wh1stle05/cmp90hx) | GPL-2.0 | 90HX patch 0017 (its retrain retry, which this repository's 170HX Gen2 patch also uses), `maskread.py`, the two-mask minimum, and the combination of 90HX pins |
| [sasha0552/nvidia-pstated](https://github.com/sasha0552/nvidia-pstated) | GPL-3.0 | Idle daemon, built and run as a separate program |

The NVIDIA driver itself is unfree and fetched from NVIDIA as in nixpkgs. `nvidia-pstated` (GPL-3.0) is built and run as a separate program, not combined with anything here.
