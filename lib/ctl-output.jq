# Text output must be ASCII too: jq -r bypasses --ascii-output for strings.
def hex4:
  . as $n | [4096,256,16,1] | map(. as $divisor | (($n / $divisor | floor) % 16) as $digit |
    "0123456789abcdef"[$digit:$digit+1]) | join("");
def safe: tojson | explode | map(
  if . >= 32 and . <= 126 then [.] | implode
  elif . <= 65535 then "\\u" + hex4
  else (. - 65536) as $n | "\\u" + (55296 + ($n / 1024 | floor) | hex4) + "\\u" + (56320 + ($n % 1024) | hex4)
  end) | join("");
def fields: map(safe) | join("  ");
def policy:
  "Startup: " + (.baseline | safe),
  "Runtime grants: " + (.grants | safe),
  "Private trust (startup only): " + (.private | safe);

if $view == "runs" then
  if length == 0 then "No active runs in this user's registry on the selected daemon."
  else "RUN (use a unique 8+ character prefix)  HARNESS  EGRESS  STATUS  PROJECT",
    (.[] | [.run,.harness,.egress,.status,.project] | fields) end
elif $view == "inspect" or $view == "config" then
  (if .run then "Run: " + .run else empty end),
  "Project: " + (.project | safe), "Harness: " + (.harness | safe), "Egress: " + (.egress | safe),
  "Image: " + (.image | safe), "State volume: " + (.volume | safe),
  (if .limits then "Limits: processes " + (.limits.pids | tostring) + ", memory " +
    (if .limits.memory == null then "none" else (.limits.memory | tostring) + " bytes" end) else empty end),
  (if .workspace then "Workspace: " + (.workspace | safe) +
    (if .workspaceVolume then " (" + (.workspaceVolume | safe) + ")" else "" end) else empty end),
  (if $view == "config" then "Network: " + (.network | safe),
    "Egress source: " + (.egressSource | safe), "Provider env file: " + (.envFile | safe) else empty end),
  (.policy | policy),
  "Startup allowance sources: " + (.policy.reasons | safe),
  "Provider keys enter agent: " + (.providerKeysEnterAgent | tostring),
  "Credentials present (names and sources only): " + ([.credentials[] | {name,source}] | safe),
  (if .policyUncertain then "POLICY UNCERTAIN: restart this run." else empty end)
elif $view == "show" then policy
elif $view == "pending" then
  "Run: " + .run,
  "Observed block events from at most 2,000 retained log lines; not waiting requests.",
  (if .policyKnown then empty else "Policy snapshot uncertain or updating; no approval candidates shown." end),
  (if (.destinations | length) == 0 then "No block events observed in this history window."
   else (.destinations[] |
     "Host: " + (.host | safe) + "  ports: " + (.ports | safe) + "  block events: " + (.events | tostring),
     "  coverage: " + .coverage + "  approval candidate: " + (.approvalCandidate | tostring) +
       "  private trust: " + (.privateTrusted | tostring),
     "  kinds: " + (.kinds | safe) + "  first: " + (.firstSeen | safe) + "  last: " + (.lastSeen | safe)),
    "Coverage is a policy snapshot, not proof of connectivity. Retry outcome is unknown." end)
elif $view == "watch" then
  [.time,.target,.kind,(if .approvalCandidate then "allowlist candidate" else "diagnostic only" end)] | fields
elif $view == "update" then
  (if .changed then
    (if .action == "allow" then "Allowed " else "Revoked runtime grant for " end) + .host + " for run " + .run + ". Policy reload confirmed."
   else "No policy change: " + .host + " " + (if .action == "allow" then "already has a runtime grant." else "has no runtime grant." end) end),
  (if .action == "allow" then "Retry the failed command manually. Grants permit uploads and downloads, not just the observed port."
   else "Revocation affects new tunnels only; existing tunnels are not closed." end),
  "Startup policy and private-address protections are unchanged."
else error("unknown output view") end
