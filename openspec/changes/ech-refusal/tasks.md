# Tasks

## 1. Probe

- [x] 1.1 Add a raw ClientHello builder to `lib/egress-probe.mjs` (server_name, supported_versions, key_share, optional ECH `0xfe0d` extension) and two checks: the control hello without ECH is forwarded through an allowed tunnel; the ECH hello's result is classified as forwarded or refused; verify by running `./verify-egress.sh allowlist` and reading both lines
- [x] 1.2 Add the capability flag to `verify-egress.sh` (off for Pipelock 3.7.1): forwarded ECH prints the known-gap warning and passes, refused fails as unexpected; with the flag on, forwarded fails; update the expected check counts; verify `./verify-egress.sh allowlist` passes and prints the warning
- [x] 1.3 Update risk 3 in `docs/architecture.md` and `docs/egress.md` from "unverified" to "confirmed at the proxy", with a decision record for the probe; verify the wording names the probe
- [x] 1.4 Remove the upstream plan and the patched-build evidence from D16 and risk 3 in `docs/egress.md` and `docs/architecture.md`; verify neither mentions an upstream pull request or `sni_reject_ech` as planned work
