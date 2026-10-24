# Tasks

## 1. Pin `.git`

- [x] 1.1 In `host_files_mounts` (`lib/host-files.sh`), mount `.git` onto `/workspace/.git` before the read-only `.git/config` and `.git/hooks` mounts, and return non-zero with the path named when either is a symlink; `rapunzel` exits on that failure in mount mode; verify with 1.2 and 1.3
- [x] 1.2 Cover the mount order and the symlink refusal in `test-control.sh`; run `./test-control.sh` and verify PASS
- [x] 1.3 Add a `swap-git-dir` attempt to `verify-host-files.sh` that expects the rename to fail and no `.git-moved` on the host, and judge the RESULT lines even when an attempt fails the in-container script; verify the attempt succeeds against `main`'s launcher and `./verify-host-files.sh` passes on this branch
- [x] 1.4 Document the pin and the symlink refusal in `AGENTS.md`, `docs/architecture.md`, and `docs/guide.md`; verify each names both

## 2. Lock pi's dependency tree

- [x] 2.1 Add `profiles/pi/package.json` pinning pi and `profiles/pi/package-lock.json` resolved no later than that release; verify the lockfile's pi entry matches the pin and carries an integrity hash
- [x] 2.2 Install pi in the `Dockerfile` with `npm ci --ignore-scripts --omit=dev` into root-owned `/usr/local/lib/pi`, run `lib/prune-foreign-platforms.mjs` in the same `RUN` layer, link `/usr/local/bin/pi`, and drop `PI_VERSION`; update the package path in `test.sh`; verify `docker build` and `./test.sh` pass
- [x] 2.3 Move pi's Renovate tracking to the npm manager and keep the regex manager only for the version quoted in the guide; verify `renovate-config-validator` accepts `renovate.json` and a local Renovate lookup against a lowered pin with a matching lockfile puts the npm manager's update (which regenerates the lockfile) and the guide's on one branch
- [x] 2.4 Update `AGENTS.md`, `docs/architecture.md` (risk 6, future work), and `docs/guide.md`; verify `grep -rn PI_VERSION` outside `openspec/` finds nothing

## 3. Provider table for the strict gateway

- [x] 3.1 Add `GATEWAY_BUILTINS` to `lib/egress.sh` and render one route per present key from it in `gateway_configure`, keeping the Anthropic subscription-token fallback; every route clears the other credential headers and drops `?key=`; verify with 3.4
- [x] 3.2 Feed the strict env filter's consumed names (`rapunzel`) and the allowlist hosts (`lib/policy.sh`) from the same table; verify `GROQ_API_KEY` alone yields the allowlist `api.groq.com`, and in strict mode `GEMINI_API_KEY` draws no warning while `HF_TOKEN` is reported as not passed
- [x] 3.3 Point pi's built-in providers at their routes in `profiles/pi/bootstrap.mjs` and remove them outside strict mode; verify a strict run with `GEMINI_API_KEY` writes `google` with `http://llm-proxy:8080/google/v1beta` and `rapunzel-gateway` to `models.json`
- [x] 3.4 Cover table-driven rendering, the Google header, `?key=` removal, the OpenRouter split, and both Anthropic credential kinds in `test-control.sh`; run `./test-control.sh` and verify PASS
- [x] 3.5 Document the routes in `docs/guide.md`, `docs/egress.md`, and `docs/architecture.md`; verify each lists the eight providers

## 4. Tool allowlist in strict mode

- [x] 4.1 In strict mode, collect `RAPUNZEL_EGRESS_ALLOW` as tool hosts and refuse an entry that equals or covers a provider host (`policy_refuse_provider_hosts` in `lib/policy.sh`); verify `rapunzel --config` exits non-zero for `*.anthropic.com` with an Anthropic key and for the custom provider's own host
- [x] 4.2 Start Pipelock beside the gateway when tool hosts exist, give the gateway its own container (`gateway_own_sidecar`), and set `HTTPS_PROXY`, `https_proxy`, `NODE_USE_ENV_PROXY=1`, and `NO_PROXY=llm-proxy`; verify a live strict run with `RAPUNZEL_EGRESS_ALLOW` has exactly the peers `egress` and `llm-proxy` on its internal network and leaves no container or network with its run label after exit
- [x] 4.3 Add the `strict-tools` mode to `verify-egress.sh` and `lib/egress-probe.mjs`, run by default; run `./verify-egress.sh` and verify all modes pass
- [x] 4.4 Record the decision as D17 in `docs/egress.md`, after D15 and D16 from `main`, and describe the mode in `docs/guide.md`, `docs/architecture.md`, and the launcher's help; verify the links resolve to `#d17-strict-mode-with-a-tool-allowlist`
- [x] 4.5 Change the `AGENTS.md` invariant that a restricted run's agent has "one peer" to cover strict mode with a tool allowlist; verify it names both sidecars

## 5. Integration

- [x] 5.1 Run every CI step locally on Colima: shellcheck 0.9.0 on every script, `node --check`, `./test-control.sh`, the pi image build and `./test.sh`, the other four harness images with `./test.sh`, `./verify-isolation.sh .`, `./verify-host-files.sh`, `./verify-workspace.sh`, `./verify-egress.sh`, and `./verify-control.sh`; verify all pass
- [x] 5.2 Run `openspec validate pin-git-lock-pi-extend-strict --strict`; verify it reports the change as valid
