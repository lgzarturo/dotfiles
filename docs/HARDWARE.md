# Hardware soportado y optimizaciones

## CPUs

### AMD Ryzen 5 PRO (laptop, mi caso Fedora 44)

- **Cores:** 6 físicos / 12 threads
- **TDP:** 15-28W
- **Detección:** `model name: AMD Ryzen 5 PRO ...`
- **Optimizaciones:**
  - `DOTFILES_CPU_PROFILE=ryzen5`
  - Perfil `laptop` automático
  - Governor: `schedutil` (kernel default optimizado)
  - Boost: AMD P-State EPP

### AMD Ryzen 9 (desktop/workstation, mi caso Windows 11)

- **Cores:** 12-16 físicos / 24-32 threads
- **TDP:** 65-170W
- **Optimizaciones:**
  - `DOTFILES_CPU_PROFILE=ryzen9`
  - Perfil `desktop` o `workstation`
  - Governor: `performance` (en desktop)
  - NUMA balancing off si 1 socket

### Apple M2

- **Cores:** 8 (4P+4E) / hasta 24 GPU
- **Detección:** `hw.physicalcpu = 8`
- **Optimizaciones:**
  - `DOTFILES_CPU_PROFILE=m2`
  - `metal` para llama.cpp
  - SSD Apple: TRIM automático, no requiere tuning

### Apple M4

- **Cores:** 10-12 (varias configuraciones)
- **Detección:** `hw.physicalcpu ≥ 10`
- **Optimizaciones:**
  - `DOTFILES_CPU_PROFILE=m4`
  - Neural Engine accesible vía Core ML
  - Unified memory: usar para Ollama sin swap

## Memoria RAM

| RAM      | Perfil      | ZRAM     | Swapfile | Swappiness |
| -------- | ----------- | -------- | -------- | ---------- |
| 4-8 GB   | laptop      | RAM/3    | 4 GB     | 30         |
| 8-16 GB  | desktop     | RAM/2    | 4 GB     | 15         |
| 16-32 GB | desktop     | RAM/2    | 4 GB     | 10         |
| 32+ GB   | workstation | 3\*RAM/4 | no crea  | 5-10       |

## Almacenamiento

### NVMe (mejor)

- I/O scheduler: `none` (kernel gestionado)
- Queue depth alto (default 1024)
- fstab: `noatime,nodiratime`
- TRIM semanal vía `fstrim.timer`

### SATA SSD

- I/O scheduler: `mq-deadline` (low-latency)
- TRIM semanal
- fstab: `noatime`

### HDD (rotacional)

- I/O scheduler: `bfq` (kernel 5.x+) o `deadline`
- Readahead más alto: `8192`
- fstab: sin `noatime` (mejora rendimiento de lecturas)

## GPU (para LLMs locales)

### AMD (Ryzen 7000+ con iGPU)

- ROCm 5.7+ soporta RDNA 2/3
- Ollama con `--rocm` flag
- llama.cpp: `LLAMA_HIPBLAS=1`

### NVIDIA

- Drivers propietarios + CUDA
- Ollama: usa CUDA automáticamente
- llama.cpp: `LLAMA_CUDA=1`

### Apple Silicon

- Metal nativo
- Ollama: optimizado para Metal
- llama.cpp: `LLAMA_METAL=1`

## Network

### TCP BBR (Linux)

- Requiere kernel ≥ 4.9
- Mejora throughput para APIs IA (Claude, OpenAI)
- Verificar: `sysctl net.ipv4.tcp_congestion_control` → `bbr`

### fq qdisc

- Coexiste con BBR
- Reduce bufferbloat

## Casos especiales

### WSL2

- Network bridgeada a Windows
- BBR dentro de WSL no afecta Windows host
- Mejor rendimiento: `wsl --shutdown` y reiniciar con kernel custom

### macOS + Rosetta

- Para binarios x86_64 en Apple Silicon
- No afecta dotfiles, pero `arch -arm64 brew install ...` es más rápido

### Dual boot Linux + Windows

- Compartir dotfiles entre ambos: usar directorio común en partición NTFS
- O repos separados con sync manual
