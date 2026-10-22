# RPC install scripts (creature-llama.cpp fork)

Read the root [AGENTS.md](../../AGENTS.md) first. Same rules apply: ASCII only (no emdash, arrows, ellipsis), short comments. This is a private fork, so committing is fine.

## Goal

Pool GPUs across machines with the ggml RPC backend.
- Master: this Windows machine (RTX 5090, 32 GB). Runs `llama-server` / `llama-cli` with `--rpc host:port,...`.
- Hosts: other machines the user sets up. Each runs `ggml-rpc-server` and exposes its GPUs.
- Network: 10GbE, trusted LAN.
- Upstream has no RPC install script. The only upstream docs are `README.md` in this folder (manual cmake build).

## Files

- `install-rpc.ps1 -Role Host|Master` builds and sets up. Windows PowerShell 5.1 compatible.
  - Host: builds `ggml-rpc-server`, creates firewall rule `llama.cpp RPC server` (TCP, local subnet only, needs Administrator), `-Start` runs it.
  - Master: builds `llama-server` and `llama-cli`, `-Hosts ip:port,...` does a TCP reachability check.
  - Build dirs: `<repo>/build-rpc-host`, `<repo>/build-rpc-master` (gitignored by `/build*`).
- `start-rpc-server.ps1` starts the host server later (`-Port -BindAddress -Device -Cache`).
- Host needs: Git, Visual Studio with C++ workload and CMake tools, CUDA toolkit, NVIDIA driver.

## Facts about the server (`rpc-server.cpp`)

- Target name is `ggml-rpc-server`, enabled by `-DGGML_RPC=ON`.
- Flags: `-H/--host` (default `127.0.0.1`), `-p/--port` (default 50052), `-d/--device`, `-c/--cache`, `-t/--threads`.
- Default bind is loopback. A host must be started with `-H 0.0.0.0` (or its LAN IP) or the master cannot connect.
- No authentication. Never expose outside a trusted LAN.
- Startup banner prints devices, for example `CUDA0: NVIDIA GeForce RTX 5090`. Use it to verify a host.
- `GGML_RPC_DEBUG=1..3` on server or client for logs. On the client also pass `-lv 5`.
- RDMA is Linux (libibverbs) and macOS only. Windows uses TCP.

## Problems found on the master, and how the script handles them

These were all real failures. A new host script must handle the same ones.

1. **VS 2026 (MSVC 14.50, `_MSC_VER` 1950) is rejected by nvcc** in CUDA 12.8, 13.0 and 13.1 (`host_config.h`: "unsupported Microsoft Visual Studio version"). The script prefers an installed toolset older than 14.50 via `vcvars64.bat -vcvars_ver=14.xx`. If none exists it adds `-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler`. That fallback built the full CUDA backend fine on 13.1. Cleaner fix: install "MSVC v143 - VS 2022 C++ x64/x86 build tools" in the VS installer.
2. **`CUDA_PATH` can point at an old toolkit.** Here it was v12.4, which cannot target Blackwell. The script scans `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*` and picks the newest that fits the GPUs: compute capability 10+ needs CUDA 12.8+, below 7.5 needs CUDA below 13.0. It passes `CMAKE_CUDA_COMPILER` and `CUDAToolkit_ROOT` explicitly and sets `CUDA_PATH` and PATH for the process.
3. **`cmake`, `ninja`, `cl` are not on PATH.** The script imports the environment from `vcvars64.bat` (found through `vswhere.exe`). VS ships cmake and ninja, so the Ninja generator is used. This also avoids needing the CUDA Visual Studio integration.
4. **GPU architecture** comes from `nvidia-smi --query-gpu=compute_cap` (`12.0` -> `120`). Building for only the installed GPUs cuts build time a lot. CMake rewrites `120` to `120a`, which is fine. Override with `-CudaArch`.
5. **CUDA runtime DLLs** (`cudart64_*`, `cublas64_*`, `cublasLt64_*`) are copied next to the exes, because there is no static cuBLAS option on Windows. Look in both `bin` and `bin\x64` of the toolkit (CUDA 13 uses `bin\x64`).
6. **PowerShell 5.1 turns native stderr into errors** when output is redirected (`2>&1`) and `$ErrorActionPreference = 'Stop'`. CMake writes harmless lines to stderr. The script sets `Continue` around cmake calls and checks `$LASTEXITCODE`.
7. **A one-element `if` result collapses to a string**, which broke `--target @targets`. Use `[string[]]$targets` and `--target $targets`.
8. **CMake cannot switch compilers in an existing build tree.** The script deletes the build dir if the cached `CMAKE_CUDA_COMPILER` differs. `-Clean` forces it.
9. **Ninja resumes** after an interrupted build, so re-running the script is safe.
10. OpenSSL is not installed, so HTTPS is disabled (CMake only warns). `-hf` downloads fail, use local `.gguf` files. Not needed on hosts.

## Verified (2026-10-22, master machine)

- `-Role Host`: full build OK (CUDA 13.1, arch 120a, MSVC 14.50 with the override). Server started on `127.0.0.1`, detected `CUDA0: NVIDIA GeForce RTX 5090`, accepted a TCP client.
- `-Role Master`: full build OK, `llama-server --help` lists `--rpc` and `-sm {none,layer,row,tensor}`. Reachability check correctly reported a dead host.

## Not verified

- Firewall rule creation (needs an elevated shell).
- A real run across two machines, and `-sm tensor` over TCP (docs say tensor split is interconnect bound, expect it to be slower than `layer` on 10GbE).
- Any host that is not Windows + NVIDIA CUDA.

## Adapting for a different host

- **Another Windows + NVIDIA host:** reuse `install-rpc.ps1 -Role Host` unchanged. It detects that host's GPU and toolkit itself. Mixed GPU generations are fine because each host builds locally.
- **Linux + NVIDIA:** follow `README.md`: `cmake -B build-rpc -DGGML_CUDA=ON -DGGML_RPC=ON`, `cmake --build build-rpc --target ggml-rpc-server`, run `build-rpc/bin/ggml-rpc-server -H 0.0.0.0 -p 50052 -c`. Open the port with `ufw`/`firewalld` for the LAN subnet only. Check nvcc vs gcc version limits and Blackwell needing CUDA 12.8+ here too.
- **Other backends:** swap `-DGGML_CUDA=ON` for the matching option (`GGML_VULKAN`, `GGML_HIP`, `GGML_METAL`), see `docs/build.md`. Untested here.
- Keep the same shape: detect hardware, pick a toolchain that really works, build only the needed target, open the firewall for the local subnet, print the host IP for the master's `--rpc`, and verify with the server banner.

## Master run command

```powershell
build-rpc-master\bin\llama-server.exe -m model.gguf -ngl 99 --rpc 192.168.x.x:50052,192.168.x.y:50052
```

Speed notes: default `-sm layer` gives capacity, not speed. See `docs/multi-gpu.md` for split modes. MoE models, speculative decoding (`-md`) and `-np` parallel slots are the practical speed options.
