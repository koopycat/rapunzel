# One hostname grammar for startup policy, runtime grants and event candidates.
def valid_host($wildcard):
  type == "string" and
  (if $wildcard then sub("^\\*\\."; "") else . end |
    length > 0 and length <= 253 and
    test("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]([a-z0-9-]*[a-z0-9])?$") and
    (split(".") | all(length <= 63)));

def covers($host):
  . == $host or (startswith("*.") and
    (.[2:] as $suffix | $host == $suffix or ($host | endswith("." + $suffix))));

def block_event:
  select(type == "object") |
  select(.event == "blocked" or .event == "sni_mismatch") |
  (.target // .connect_host // "") as $target |
  ((try ($target | ascii_downcase | capture("^(?<host>[^:]+)(:(?<port>[0-9]{1,5}))?$") |
    select(.host | valid_host(false)) |
    select(.port == null or (.port | tonumber | . >= 1 and . <= 65535))) catch null) // null) as $parsed |
  {time:(if (.time | type) == "string" then .time else null end),
   host:($parsed.host // null),port:(($parsed.port // null) | if . == null then . else tonumber end),
   target:(if $parsed != null then ($parsed.host + (if $parsed.port != null then ":" + $parsed.port else "" end))
           else "[invalid target redacted]" end),
   kind:(if .event == "sni_mismatch" then "TLS/SNI violation"
         elif .scanner == "ssrf" then "address protection"
         elif .display_label == "dns_timeout" or .display_label == "dns_no_such_host" or .display_label == "dns_resolver_error" then .display_label
         elif .scanner == "allowlist" then "destination not allowed"
         else "other" end),
   approvalCandidate:($parsed != null and .event == "blocked" and .scanner == "allowlist" and .method == "CONNECT" and
     (.display_label != "dns_timeout" and .display_label != "dns_no_such_host" and .display_label != "dns_resolver_error"))};

def pending($run; $metadata; $known):
  {schemaVersion:1,run:$run,historyLimit:2000,policyKnown:$known,
   note:"Observed block events in retained log history, not requests waiting for approval. Coverage is a metadata snapshot; retry outcome is unknown.",
   destinations:(group_by(.host) | map(
     . as $events | .[0].host as $host |
     (if $known == false then "unknown"
      elif $host == null then "invalid"
      elif any($metadata.policy.baseline[]; covers($host)) then "startup"
      elif any($metadata.policy.grants[]; . == $host) then "runtime"
      else "not-covered" end) as $coverage |
     {host:$host,ports:(map(.port) | map(select(. != null)) | unique),
      events:length,firstSeen:(map(.time) | map(select(. != null)) | min),
      lastSeen:(map(.time) | map(select(. != null)) | max),kinds:(map(.kind) | unique),
      coverage:$coverage,privateTrusted:($host != null and any($metadata.policy.private[]; . == $host)),
      approvalCandidate:($coverage == "not-covered" and all($events[]; .approvalCandidate))}))};
