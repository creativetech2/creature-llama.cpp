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
  - Host: builds `ggml-rpc-server`, creates firewall rules `llama.cpp RPC server` (TCP 50052) and `llama.cpp RPC stats` (TCP 50053), both local subnet only, needs Administrator. `-Start` runs the server.
  - Master: builds `llama-server` and `llama-cli`, `-Hosts ip:port,...` does a TCP reachability check, `-BuildUi` builds the Web UI from source (`-DLLAMA_BUILD_UI=ON -DLLAMA_USE_PREBUILT_UI=OFF`; stops if `tools/ui/dist` exists, since it would be embedded instead).
  - Build dirs: `<repo>/build-rpc-host`, `<repo>/build-rpc-master` (gitignored by `/build*`).
- `start-rpc-server.ps1` starts the host server and its stats agent (`-Port -StatsPort -BindAddress -Device -Cache -NoAgent`).
- `stats-agent.ps1` serves `GET /stats` JSON on port 50053 (nvidia-smi GPUs, CPU, RAM, NIC rates, RPC server state). A background runspace samples every 0.5 s, requests read the latest JSON.
- `start-master.ps1` starts `llama-server` in router mode: `--models-dir --models-preset models.ini --models-max 1 --rpc <hosts> --metrics`, port 9931. It checks that every host is reachable first.
- `add-model.ps1` copies or downloads (`curl.exe`) a `.gguf` into the models folder, then calls `GET /models?reload=1`.
- `models.ini` is the router preset file (`[*]` defaults, per-model sections, `alias`, `tensor-split`, `model-draft`).
- Server side: `tools/server/server-rpc-stats.cpp` implements `GET /rpc/stats`; `common_params::rpc_servers` keeps the raw `--rpc` string (set in `common/arg.cpp`).
- UI side (`tools/ui`): routes `src/routes/rpc` and `src/routes/models`, store `src/lib/stores/rpc.svelte.ts`, service `src/lib/services/rpc.service.ts`, components `src/lib/components/app/rpc/`, helpers and tests `src/lib/utils/rpc-stats.ts`, `tests/unit/rpc-stats.test.ts`. The sidebar entries are in `src/lib/constants/ui.constants.ts`.
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

- Two real hosts (RTX 4090 at 192.168.1.15, 3x RTX 2080 Ti at 192.168.1.44) were reachable from the master on 50052.
- `GET /rpc/stats` on a router: 401 without the API key, 200 with it, master agent reachable, hosts with the old scripts reported `reachable:false` without stalling or crashing. UI built from source: svelte-check 0 errors, 730 unit tests pass (14 new).
- The router (`start-master.ps1`) started against both hosts and listed the LM Studio models folder read-only.

## Router mode and the single-client RPC server

- `ggml-rpc-server` serves one client at a time (`ggml-rpc.cpp` accept loop, listen backlog 1). A loaded model's child process keeps its connection to every host, so two models on the same hosts would hang the second. Hence `--models-max 1`: loading B evicts A (LRU) first, up to the 10 s stop-timeout.
- The router connects to the hosts briefly at startup, then closes. A host held by another client makes the router hang, a host that is down makes it abort.
- Router children inherit `--rpc` and the environment. `--sleep-idle-seconds` is risky with RPC (a failed wake-up aborts).
- Never call `ggml_backend_dev_memory` from an HTTP handler: it round-trips to the host and aborts the process when the host is down. Remote stats come from the HTTP agent instead.

## Gotchas found while testing

- Port 8080 on the master belongs to NVIDIA's Personal AI Router (`nvpair-proxy.exe`, restarted by `PAIR.exe`); this fork's server default port is 9931.
- The embedded UI is gzipped: `curl` without `--compressed` gets `415 gzip is not supported by this browser`.
- `$PSScriptRoot` in a `param()` default came up empty when the script was started with `Start-Process powershell -File`; compute such defaults in the script body.
- The Claude-in-Chrome extension could not load `http://127.0.0.1:9931` here (error page, even for `/health`) while `curl` could, so the UI was never viewed in that browser.

## Not verified

- The RPC and Models tabs visually (see above), and loading a model through the router across the pool.
- The stats agent on the real hosts (they ran the old scripts when tested).
- Firewall rule creation (needs an elevated shell).
- `-sm tensor` over TCP (docs say tensor split is interconnect bound, expect it to be slower than `layer` on 10GbE).
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
