<!-- Source for concepts.html. Regenerate with the html-output skill's scripts/md2html.py. -->
<style>
  .concepts { --safe: #74dec5; --safe-bg: #112b29; --agent: #f1bd75; --agent-bg: #30271b; --stop: #ff969d; --stop-bg: #321e25; }
  :root[data-theme="light"] .concepts { --safe: #146c5a; --safe-bg: #e0f1eb; --agent: #8b5513; --agent-bg: #fff0d9; --stop: #b02e42; --stop-bg: #fde9ed; }
  .concepts .eyebrow { margin: 0 0 18px; color: var(--safe); font: 600 12px/1.5 "SF Mono", Menlo, Consolas, monospace; text-transform: uppercase; letter-spacing: .15em; }
  .concepts .hero { display: grid; grid-template-columns: 1fr 245px; align-items: center; gap: 44px; margin-bottom: 30px; }
  .concepts h1 { margin: 0 0 24px; max-width: 16ch; font-size: clamp(38px, 5.8vw, 68px); line-height: 1.04; letter-spacing: -.055em; }
  .concepts .lede { max-width: 58ch; color: var(--muted); font-size: 19px; line-height: 1.65; }
  .concepts .tower { width: 100%; height: auto; color: var(--safe); }
  .concepts .tower .masonry { fill: var(--surface); stroke: var(--border); stroke-width: 1.5; }
  .concepts .tower text { font: 11px "SF Mono", Menlo, Consolas, monospace; fill: var(--muted); }
  .concepts .pills, .concepts .jump-links { display: flex; flex-wrap: wrap; gap: 9px 18px; }
  .concepts .pills { margin: 22px 0; }
  .concepts .pill { display: inline-block; padding: 5px 10px; border: 1px solid var(--border); border-radius: 999px; font-size: 12px; color: var(--muted); }
  .concepts .jump-links { padding: 18px 0; border-block: 1px solid var(--border); font-size: 13px; }
  .concepts section { margin-top: 66px; scroll-margin-top: 24px; }
  .concepts .section-heading { display: flex; align-items: baseline; gap: 15px; margin-bottom: 12px; }
  .concepts .section-number { color: var(--safe); font: 500 13px "SF Mono", Menlo, Consolas, monospace; }
  .concepts h2 { margin: 0; font-size: clamp(24px, 3vw, 32px); }
  .concepts h3 { margin: 0 0 8px; font-size: 18px; }
  .concepts .intro { max-width: 74ch; margin: 10px 0 24px; color: var(--muted); }
  .concepts .legend { display: flex; flex-wrap: wrap; gap: 12px 24px; margin: 18px 0; font-size: 12px; color: var(--muted); }
  .concepts .legend span::before { content: ""; display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 7px; background: var(--safe); }
  .concepts .legend .untrusted::before { background: var(--agent); }
  .concepts .legend .blocked::before { background: var(--stop); }
  .concepts .board { border: 1px solid var(--border); border-radius: 16px; overflow: hidden; background: var(--stripe); }
  .concepts .zone { padding: 24px; }
  .concepts .zone + .zone { border-top: 1px solid var(--border); }
  .concepts .zone-title { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 8px; margin: 0 0 17px; font: 600 11px/1.5 "SF Mono", Menlo, Consolas, monospace; letter-spacing: .07em; text-transform: uppercase; color: var(--muted); }
  .concepts .host-inputs { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; }
  .concepts .node { min-width: 0; background: var(--bg); border: 1px solid var(--border); border-radius: 10px; padding: 18px; }
  .concepts .node p { margin: 6px 0 0; color: var(--muted); font-size: 13px; line-height: 1.65; }
  .concepts .node .label { display: block; margin-bottom: 8px; font: 600 10px/1.4 "SF Mono", Menlo, Consolas, monospace; letter-spacing: .06em; text-transform: uppercase; }
  .concepts .trusted-node { border-top: 3px solid var(--safe); }
  .concepts .trusted-node .label { color: var(--safe); }
  .concepts .blocked-node { border-top: 3px solid var(--stop); }
  .concepts .blocked-node .label { color: var(--stop); }
  .concepts .mount-note { margin: 0; padding: 12px 24px; border-top: 1px dashed var(--border); color: var(--muted); font-size: 12px; text-align: center; }
  .concepts .network { border: 1px dashed var(--safe); border-radius: 12px; padding: 18px; }
  .concepts .network-label { color: var(--safe); font: 500 11px/1.6 "SF Mono", Menlo, Consolas, monospace; margin: 0 0 16px; }
  .concepts .runtime { display: grid; grid-template-columns: minmax(0, 1fr) 90px minmax(0, 1fr); align-items: stretch; }
  .concepts .agent-node { border: 1px solid var(--agent); background: var(--agent-bg); }
  .concepts .agent-node .label { color: var(--agent); }
  .concepts .agent-node h3 { font-size: 23px; }
  .concepts .node .mount { padding: 9px 11px; margin-top: 10px; background: var(--bg); border-radius: 6px; font-size: 12px; }
  .concepts .connector { align-self: center; text-align: center; color: var(--safe); font: 500 11px/1.5 "SF Mono", Menlo, Consolas, monospace; }
  .concepts .connector b { display: block; font-size: 26px; font-weight: 400; }
  .concepts .tails { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-top: 18px; }
  .concepts .tail { padding: 0 8px; font-size: 13px; color: var(--muted); }
  .concepts .tail strong { display: block; margin-bottom: 4px; }
  .concepts .note { padding: 16px 20px; border-left: 3px solid var(--safe); background: var(--safe-bg); border-radius: 0 8px 8px 0; font-size: 14px; }
  .concepts .note strong { color: inherit; }
  .concepts .note.warning { border-color: var(--agent); background: var(--agent-bg); }
  .concepts .cards { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
  .concepts .card { display: flex; flex-direction: column; min-width: 0; padding: 23px; border: 1px solid var(--border); border-radius: 12px; background: var(--stripe); }
  .concepts .card .tag { align-self: flex-start; padding: 3px 8px; margin-bottom: 16px; border: 1px solid var(--border); border-radius: 5px; font: 500 10px/1.6 "SF Mono", Menlo, Consolas, monospace; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); }
  .concepts .card h3 { font-size: 23px; }
  .concepts .card p { font-size: 14px; color: var(--muted); }
  .concepts .card.safe { border-top: 3px solid var(--safe); }
  .concepts .card .route { display: grid; gap: 6px; padding: 16px 0; margin: 8px 0; border-block: 1px solid var(--border); text-align: center; font-size: 13px; }
  .concepts .route span { display: block; }
  .concepts .route .arrow { color: var(--muted); font-size: 17px; line-height: 1; }
  .concepts .route .proxy { color: var(--safe); font-weight: 600; }
  .concepts .facts { margin: 8px 0 0; padding: 0; list-style: none; font-size: 13px; }
  .concepts .facts li { margin: 9px 0; }
  .concepts .facts li::before { content: "→"; margin-right: 8px; color: var(--muted); }
  .concepts .card .bottom { margin-top: auto; padding-top: 16px; font-size: 12px; }
  .concepts .source-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-top: 20px; }
  .concepts .source-grid .node { padding: 16px 18px; }
  .concepts .source-grid h3 { font-size: 15px; }
  .concepts .split { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
  .concepts .split .card h3 { font-size: 21px; }
  .concepts .lifetime { font: 500 11px "SF Mono", Menlo, Consolas, monospace; color: var(--safe); margin-bottom: 12px; }
  .concepts .state-path { display: block; padding: 12px; border-radius: 6px; background: var(--bg); overflow-wrap: anywhere; font: 12px/1.7 "SF Mono", Menlo, Consolas, monospace; }
  .concepts .profiles { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 10px; margin-top: 22px; }
  .concepts .profile { min-width: 0; padding: 16px 13px; border: 1px solid var(--border); border-radius: 9px; }
  .concepts .profile h3 { font-size: 16px; }
  .concepts .profile p { color: var(--muted); font-size: 11px; margin: 4px 0; }
  .concepts .profile .support { color: var(--safe); font-size: 11px; }
  .concepts .timeline { list-style: none; padding: 0; margin: 24px 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; counter-reset: step; }
  .concepts .timeline li { counter-increment: step; margin: 0; padding: 18px 18px 18px 48px; position: relative; border-top: 1px solid var(--border); }
  .concepts .timeline li::before { content: "0" counter(step); position: absolute; left: 9px; top: 20px; color: var(--safe); font: 12px "SF Mono", Menlo, Consolas, monospace; }
  .concepts .timeline strong { display: block; font-size: 15px; }
  .concepts .timeline p { margin: 6px 0 0; color: var(--muted); font-size: 13px; }
  .concepts .security .card:first-child { border-top: 3px solid var(--safe); }
  .concepts .security .card:last-child { border-top: 3px solid var(--agent); }
  .concepts .checks { display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0; }
  .concepts .checks code { border: 1px solid var(--border); padding: 6px 10px; font-size: 11px; }
  .concepts .grant-board { padding: 24px; border: 1px solid var(--safe); border-radius: 12px; background: var(--safe-bg); }
  .concepts .grant-status { color: var(--safe); font: 600 11px/1.5 "SF Mono", Menlo, Consolas, monospace; letter-spacing: .04em; text-transform: uppercase; }
  .concepts .approval-flow { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; list-style: none; padding: 0; margin: 24px 0; counter-reset: approval; }
  .concepts .approval-flow li { counter-increment: approval; border-top: 1px solid var(--safe); padding-top: 12px; margin: 0; font-size: 13px; }
  .concepts .approval-flow li::before { content: counter(approval) " /"; display: block; color: var(--safe); font: 11px "SF Mono", Menlo, Consolas, monospace; margin-bottom: 10px; }
  .concepts .approval-flow strong { display: block; }
  .concepts .approval-flow span { display: block; color: var(--muted); margin-top: 5px; font-size: 12px; }
  .concepts .grant-board p { font-size: 14px; }
  .concepts details { border-bottom: 1px solid var(--border); padding: 16px 0; }
  .concepts summary { cursor: pointer; font-size: 15px; font-weight: 600; }
  .concepts details p { color: var(--muted); font-size: 14px; max-width: 74ch; }
  .concepts .source-map { display: grid; grid-template-columns: 1fr 1fr; gap: 0 32px; margin-top: 20px; }
  .concepts .source-map a { display: block; padding: 12px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
  .concepts .source-map a span { color: var(--muted); display: block; font-size: 12px; margin-top: 3px; }
  .concepts code { hyphens: manual; white-space: nowrap; }
  .concepts code.command { white-space: normal; }
  .concepts .footer { margin-top: 40px; color: var(--muted); font-size: 12px; }
  @media (max-width: 800px) {
    .concepts .hero { grid-template-columns: 1fr 180px; gap: 20px; }
    .concepts .cards { grid-template-columns: 1fr; }
    .concepts .card .route { grid-template-columns: 1fr 22px 1fr 22px 1fr; align-items: center; }
    .concepts .route .arrow { transform: rotate(-90deg); }
    .concepts .profiles { grid-template-columns: repeat(3, 1fr); }
    .concepts .timeline { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .concepts .approval-flow { grid-template-columns: 1fr; gap: 16px; }
    .concepts .approval-flow li { padding-left: 32px; position: relative; }
    .concepts .approval-flow li::before { position: absolute; left: 0; top: 16px; }
  }
  @media (max-width: 600px) {
    .concepts .hero { grid-template-columns: 1fr; }
    .concepts .tower { display: none; }
    .concepts .lede { font-size: 17px; }
    .concepts section { margin-top: 44px; }
    .concepts .zone, .concepts .grant-board { padding: 18px; }
    .concepts .host-inputs, .concepts .split, .concepts .source-grid, .concepts .tails, .concepts .source-map { grid-template-columns: 1fr; }
    .concepts .runtime { grid-template-columns: 1fr; }
    .concepts .connector { padding: 8px 0; }
    .concepts .connector b { transform: rotate(90deg); }
    .concepts .connector span { display: none; }
    .concepts .network { padding: 12px; }
    .concepts .node, .concepts .card { padding: 17px; }
    .concepts .profiles { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .concepts .timeline { grid-template-columns: 1fr; }
    .concepts .section-heading { gap: 10px; }
  }
  @media print {
    .concepts { --safe: #146c5a; --safe-bg: #e0f1eb; --agent: #8b5513; --agent-bg: #fff0d9; --stop: #b02e42; --stop-bg: #fde9ed; }
    .concepts .hero { grid-template-columns: 1fr 160px; }
    .concepts h1 { font-size: 32pt; }
    .concepts .lede { font-size: 12pt; }
    .concepts section { margin-top: 28pt; }
    .concepts h2 { font-size: 19pt; }
    .concepts .jump-links { display: none; }
    .concepts .card, .concepts .node, .concepts .grant-board, .concepts .network, .concepts .timeline li { break-inside: avoid; }
    .concepts .cards, .concepts .split { grid-template-columns: 1fr; }
    .concepts .profiles { grid-template-columns: repeat(3, 1fr); }
    .concepts .source-map a[href]::after { content: none; }
    .concepts details { display: none; }
  }
</style>

<div class="concepts">
<header>
  <p class="eyebrow">Rapunzel / a visual field guide</p>
  <div class="hero">
    <div>
      <h1>Give the agent a project.<br>Not your machine.</h1>
      <p class="lede">A Docker sandbox for coding agents. One project mount, separate agent state, and an optional controlled path to the network. The security boundary lives outside the agent.</p>
    </div>
    <svg class="tower" viewBox="0 0 245 300" role="img" aria-labelledby="tower-title tower-desc">
      <title id="tower-title">The Rapunzel tower</title>
      <desc id="tower-desc">An agent inside a tower with three layers: project, agent, and state. A single controlled connection leads out.</desc>
      <path class="masonry" d="M49 84 L49 40 L71 40 L71 61 L94 61 L94 40 L117 40 L117 61 L140 61 L140 40 L163 40 L163 84 Z"/>
      <rect class="masonry" x="57" y="84" width="98" height="165" rx="4"/>
      <path d="M57 137H155 M57 192H155" fill="none" stroke="currentColor" stroke-opacity=".35"/>
      <rect x="81" y="101" width="50" height="22" rx="5" fill="currentColor" fill-opacity=".13"/>
      <text x="106" y="116" text-anchor="middle">agent</text>
      <text x="106" y="169" text-anchor="middle">project</text>
      <text x="106" y="223" text-anchor="middle">state</text>
      <path d="M131 112H188V221 Q188 237 204 237H224" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      <circle cx="188" cy="172" r="12" fill="var(--bg)" stroke="currentColor" stroke-width="2"/>
      <path d="M184 172L187 175L193 168" fill="none" stroke="currentColor" stroke-width="1.5"/>
      <path d="M32 250H180" fill="none" stroke="var(--border)" stroke-width="1.5"/>
      <text x="123" y="280" text-anchor="middle">one way out. your rules.</text>
    </svg>
  </div>
  <div class="pills"><span class="pill">Host-side enforcement</span><span class="pill">Five harness profiles</span><span class="pill">Three egress modes</span><span class="pill">No host home mount</span></div>
  <nav class="jump-links" aria-label="Guide sections"><a href="#boundary">The boundary</a><a href="#egress">Network modes</a><a href="#state">State &amp; profiles</a><a href="#lifecycle">A run</a><a href="#limits">Security limits</a><a href="#grants">Runtime grants</a><a href="#code">Code map</a></nav>
</header>

<section id="boundary" aria-labelledby="boundary-heading">
  <div class="section-heading"><span class="section-number">01</span><h2 id="boundary-heading">The boundary, not a permission prompt.</h2></div>
  <p class="intro">Treat the harness, its shell commands, the project, and the agent’s saved state as untrusted. The host launcher and Docker enforce what those processes can access.</p>
  <div class="legend"><span>Trusted enforcement</span><span class="untrusted">Untrusted workload</span><span class="blocked">Not exposed</span></div>
  <div class="board">
    <div class="zone">
      <div class="zone-title"><span>Your host / trusted control</span><span>Choose what crosses the boundary</span></div>
      <div class="host-inputs">
        <div class="node"><span class="label">The one project</span><h3>Selected directory</h3><p>Read-write at <code>/workspace</code>, with <code>.git</code> pinned in place and its config, hooks, and an in-project hooksPath read-only. With <code>--clone</code> nothing from the host is mounted: the agent works on a clone in a volume.</p></div>
        <div class="node trusted-node"><span class="label">Trusted controller</span><h3>The launcher</h3><p>Selects the profile, filters environment names, prepares volume ownership, and creates the network policy.</p></div>
        <div class="node blocked-node"><span class="label">Not mounted</span><h3>The rest of your host</h3><p>No host home, <code>~/.ssh</code>, host agent state, or Docker socket. Files outside the chosen project stay outside.</p></div>
      </div>
    </div>
    <p class="mount-note">↓ One project bind mount (none with <code>--clone</code>) + allowlisted runtime variables. Never the whole host environment.</p>
    <div class="zone">
      <div class="zone-title"><span>Docker engine / restricted-mode view</span><span>Fresh networks and sidecars per run</span></div>
      <div class="network">
        <p class="network-label">INTERNAL NETWORK · --internal + isolated gateway mode · Docker Engine 28+</p>
        <div class="runtime">
          <div class="node agent-node"><span class="label">Untrusted / no root / no capabilities</span><h3>Agent container</h3><p>pi, Claude Code, Codex, dsh, or opencode, plus every tool and shell process it starts.</p><div class="mount"><code>/workspace</code> → selected project, or its clone</div><div class="mount">Profile state path → named Docker volume</div></div>
          <div class="connector" aria-label="Only way out through the sidecar"><b aria-hidden="true">→</b><span>only<br>way out</span></div>
          <div class="node trusted-node"><span class="label">Trusted / pinned image</span><h3>Egress sidecars</h3><p><strong>Allowlist:</strong> Pipelock checks the destination and TLS server name.</p><p><strong>Strict:</strong> Caddy forwards fixed provider routes and supplies the real credentials; with a tool allowlist, Pipelock runs beside it.</p><p>The agent cannot mount, edit, or administer the sidecar’s config.</p></div>
        </div>
      </div>
      <div class="tails">
        <div class="tail"><strong>↕ Persistent Docker volume</strong>Settings, logins, sessions, and extensions. Separate for each project and harness; not a copy of host agent state.</div>
        <div class="tail"><strong>↓ Per-run outbound bridge → upstreams</strong>Only the sidecars join this bridge. No shared default bridge; inter-container communication is disabled.</div>
      </div>
    </div>
  </div>
  <p class="note"><strong>Fail closed:</strong> in restricted modes, a tool that ignores proxy settings has no direct route to the internet. External DNS, metadata access, and host access are also probed by the verification scripts.</p>
</section>

<section id="egress" aria-labelledby="egress-heading">
  <div class="section-heading"><span class="section-number">02</span><h2 id="egress-heading">Three ways to leave the tower.</h2></div>
  <p class="intro"><code>RAPUNZEL_EGRESS</code> selects a network policy. Destination restriction and credential isolation are different protections.</p>
  <div class="cards">
    <article class="card"><span class="tag">Default / compatibility</span><h3>open</h3><p>Keep filesystem and process isolation, with normal outbound networking.</p><div class="route"><span>Agent + key</span><span class="arrow" aria-hidden="true">↓</span><span>Docker bridge</span><span class="arrow" aria-hidden="true">↓</span><span>Internet</span></div><ul class="facts"><li>No egress sidecar</li><li>Provider credentials enter the agent</li><li>Optional <code>RAPUNZEL_NETWORK=none</code> for offline runs</li></ul><p class="bottom">All five harnesses. dsh’s web UI is published on host loopback only, in open mode.</p></article>
    <article class="card safe"><span class="tag">Destination control</span><h3>allowlist</h3><p>Permit named destinations through an HTTPS CONNECT proxy.</p><div class="route"><span>Agent + key</span><span class="arrow" aria-hidden="true">↓</span><span class="proxy">Pipelock</span><span class="arrow" aria-hidden="true">↓</span><span>Allowed hosts</span></div><ul class="facts"><li>TLS SNI must match CONNECT host</li><li>Private addresses blocked unless explicitly trusted</li><li><code>HTTPS_PROXY</code> set; <code>HTTP_PROXY</code> not set</li><li>Exact hosts can be granted for one run from the host</li></ul><p class="bottom">All five harnesses. OAuth logins are possible with the required login hosts allowed.</p></article>
    <article class="card safe"><span class="tag">Credential isolation</span><h3>strict</h3><p>Keep real provider API keys in a fixed-route credential gateway.</p><div class="route"><span>Agent + placeholder</span><span class="arrow" aria-hidden="true">↓</span><span class="proxy">Caddy + real key</span><span class="arrow" aria-hidden="true">↓</span><span>Provider APIs</span></div><ul class="facts"><li>Eight built-in provider routes plus <code>/custom</code></li><li>Gateway always overwrites authentication</li><li>Unknown routes return 403</li><li>Optional tool allowlist; provider hosts refused there</li></ul><p class="bottom">pi, opencode, and Claude Code. API keys or a host-issued Claude setup token, not logins made inside the sandbox.</p></article>
  </div>
  <p class="note warning"><strong>A host allowance is not a read-only allowance.</strong> A CONNECT tunnel hides HTTPS methods, paths, and bodies from the proxy. Allowing GitHub or a registry opens an upload path as well as a download path. No TLS interception is configured.</p>
  <h3 style="margin-top: 28px;">Where the allowlist comes from</h3>
  <div class="source-grid">
    <div class="node"><h3>Provider settings &amp; profile defaults</h3><p>Built-in provider keys (Anthropic, OpenAI, OpenRouter, Gemini, Groq, Mistral, DeepSeek, xAI) add their API hosts; a custom base URL adds its host. Profiles may declare fixed provider hosts.</p></div>
    <div class="node"><h3>Explicit login providers</h3><p><code>RAPUNZEL_EGRESS_LOGINS</code> adds the model and token-refresh hosts for the named providers.</p></div>
    <div class="node"><h3>Extra public destinations</h3><p><code>RAPUNZEL_EGRESS_ALLOW</code> adds hosts. Wildcards are supported, but exact names grant less access.</p></div>
    <div class="node"><h3>Deliberate private destinations</h3><p><code>RAPUNZEL_EGRESS_ALLOW_PRIVATE</code> trusts exact host names that resolve privately. No wildcards; metadata stays blocked.</p></div>
  </div>
  <p class="intro">Host-controlled input only. Never derive policy from <code>auth.json</code>, project content, or other agent-writable state. Policy is generated at startup; during an allowlist run, only the operator can add or revoke exact hosts from the host (<a href="#grants">06</a>).</p>
</section>

<section id="state" aria-labelledby="state-heading">
  <div class="section-heading"><span class="section-number">03</span><h2 id="state-heading">Disposable execution. Persistent agent state.</h2></div>
  <p class="intro">A container is a run. A volume belongs to a project–harness pair. Changing the harness does not mean sharing its configuration or logins.</p>
  <div class="split">
    <article class="card"><div class="lifetime">LIFETIME / ONE RUN</div><h3>Execution &amp; network resources</h3><p>The agent container is removed after it exits. In restricted modes, the sidecars, their anonymous config volumes, and both networks are removed too.</p><p>Owner labels let a later restricted run sweep resources left by a dead launcher on the same host.</p></article>
    <article class="card"><div class="lifetime">LIFETIME / ACROSS RUNS</div><h3>Per-project, per-harness volume</h3><p>Stores settings, sessions, logins, trust decisions, and extensions. The launcher prepares ownership for the caller’s UID/GID before each run.</p><span class="state-path">rapunzel-&lt;harness&gt;-&lt;12-character path hash&gt;</span><p>The agent can modify this state. Persistence is useful, but it is not a trusted policy source. With <code>--clone</code>, a second volume per project and harness holds the workspace clone.</p></article>
  </div>
  <div class="profiles" aria-label="Harness profiles and strict-mode support">
    <article class="profile"><h3>pi</h3><p>Default harness</p><p class="support">open · allowlist · strict</p></article>
    <article class="profile"><h3>Claude Code</h3><p>claude profile</p><p class="support">open · allowlist · strict</p></article>
    <article class="profile"><h3>Codex CLI</h3><p>codex profile</p><p class="support">open · allowlist</p></article>
    <article class="profile"><h3>DeepSeek</h3><p>dsh profile · headless in allowlist</p><p class="support">open · allowlist</p></article>
    <article class="profile"><h3>opencode</h3><p>XDG paths inside its volume</p><p class="support">open · allowlist · strict</p></article>
  </div>
  <p class="intro">Profiles declare data: command, state paths, environment names, and supported modes. They do not get to weaken launcher controls. Each harness has its own image stage; Copilot CLI is planned, not implemented.</p>
</section>

<section id="lifecycle" aria-labelledby="lifecycle-heading">
  <div class="section-heading"><span class="section-number">04</span><h2 id="lifecycle-heading">From a command to a contained session.</h2></div>
  <p class="intro"><code class="command">./rapunzel [PROJECT_DIR [harness arguments…]]</code> uses the same boundary for normal runs, <code>--shell</code>, and <code>--exec</code>.</p>
  <ol class="timeline">
    <li><strong>Resolve &amp; validate</strong><p>Choose the repository-owned profile and project. Refuse root. Check Docker reachability and image availability.</p></li>
    <li><strong>Prepare state &amp; inputs</strong><p>Set volume ownership; with <code>--clone</code>, seed or update the workspace clone from a git bundle. Filter runtime variables and any env file; reject interpreter and loader overrides.</p></li>
    <li><strong>Build the network boundary</strong><p>For restricted modes, create both networks, render policy, start the sidecars, and wait for readiness.</p></li>
    <li><strong>Protect &amp; record host files</strong><p>In mount mode, pin <code>.git</code>, add read-only git control-file mounts, and snapshot files the host may later execute.</p></li>
    <li><strong>Bootstrap &amp; run</strong><p>Map the arbitrary UID/GID to “agent” with libnss-wrapper, generate harness configuration, then start the command.</p></li>
    <li><strong>Clean up &amp; report</strong><p>Remove secrets and per-run egress resources, restore terminal modes, and report changed host-executed files; with <code>--clone</code>, fetch the agent’s commits into <code>rapunzel-&lt;harness&gt;/*</code> for review.</p></li>
  </ol>
</section>

<section id="limits" aria-labelledby="limits-heading">
  <div class="section-heading"><span class="section-number">05</span><h2 id="limits-heading">What the tower does—and does not—protect.</h2></div>
  <p class="intro">The Docker engine, host, launcher, and pinned sidecars are trusted. A compromised agent is assumed. Container-runtime and kernel escapes remain outside the intended boundary.</p>
  <div class="split security">
    <article class="card"><h3>Enforced outside the agent</h3><ul class="facts"><li>One selected host project, not your home directory</li><li>Non-root identity, no Linux capabilities, no-new-privileges, a process limit</li><li>Explicit environment forwarding, not ambient secrets</li><li>No direct off-network path in restricted modes</li><li>Read-only git config and hooks, with <code>.git</code> pinned so it cannot be swapped</li><li>Provider API keys outside the agent in strict mode</li></ul></article>
    <article class="card"><h3>Still requires care</h3><ul class="facts"><li>The agent can read and edit the project you give it</li><li>Allowed destinations can receive project data</li><li>In mount mode, most host-executed files are reported, not blocked</li><li>Agent-volume modifications survive into later sessions</li><li>OAuth tokens stay inside agent state</li><li>Encrypted Client Hello can hide the real site behind an allowed name</li><li>Docker Desktop mount behavior and untested WSL2 support are documented limitations</li></ul></article>
  </div>
  <p class="note warning"><strong>The indirect host-execution risk:</strong> an agent can edit <code>.envrc</code>, editor tasks, package scripts, or CI configuration. Egress control cannot protect you if you later execute those changes on the host without review.</p>
  <div class="checks" aria-label="Verification commands"><code>./test.sh</code><code>./test-control.sh</code><code>./verify-isolation.sh</code><code>./verify-host-files.sh</code><code>./verify-workspace.sh</code><code>./verify-egress.sh allowlist</code><code>./verify-egress.sh strict</code><code>./verify-egress.sh strict-tools</code><code>./verify-control.sh</code></div>
  <p class="intro">Verification runs through the real launcher. Egress probes try direct IPv4/IPv6, DNS, metadata, host access, denied destinations, SNI mismatch, and Encrypted Client Hello. Strict-mode checks also verify credential replacement. Image publication calls CI and waits for it to pass.</p>
  <details><summary>Why not rely on the harness’s own approvals?</summary><p>The threat model includes a hostile agent process and its child tools. A permission prompt inside that process is not an independent boundary. Harness approvals can add useful friction, but Docker and the sidecar must still enforce the outer limit.</p></details>
  <details><summary>Why a sidecar instead of firewall rules inside the agent?</summary><p>The sidecar keeps enforcement outside the untrusted container without granting it NET_ADMIN. Internal Docker networking works across Linux and Docker VM setups. Isolated gateway mode avoids the host-side bridge address a plain internal network would retain.</p></details>
  <details><summary>Does allowlist mode guarantee all traffic is HTTPS?</summary><p>CONNECT tunnels require TLS with matching SNI, and the launcher does not set HTTP_PROXY. However, Pipelock can also forward deliberately crafted plain-HTTP proxy requests to allowed hosts, as documented in egress decision D4. An unset variable is not a proxy-side prohibition of every cleartext request.</p></details>
</section>

<section id="grants" aria-labelledby="grants-heading">
  <div class="section-heading"><span class="section-number">06</span><h2 id="grants-heading">Runtime grants: one more host, for one run.</h2></div>
  <p class="intro">An allowlist run's policy can grow from the host while the agent keeps running. Nothing in the project or the agent volume can trigger it.</p>
  <div class="grant-board">
    <div class="grant-status">Implemented / allowlist mode only</div>
    <ol class="approval-flow">
      <li><strong>Attempt</strong><span>The agent requests an unlisted destination.</span></li>
      <li><strong>Deny &amp; surface</strong><span>Pipelock refuses the tunnel; <code>egress pending</code> or <code>egress watch</code> shows the host.</span></li>
      <li><strong>You approve</strong><span><code class="command">rapunzel-ctl egress allow RUN_ID HOST</code>: an exact name, this run only, no wildcards.</span></li>
      <li><strong>Confirmed reload</strong><span>A networkless validator checks the candidate; the live proxy must acknowledge its exact hash.</span></li>
      <li><strong>Agent retries</strong><span>New tunnels are admitted under the updated policy.</span></li>
    </ol>
    <p><strong>Failure is safe:</strong> a rejected candidate leaves the policy unchanged, an unacknowledged reload is rolled back, and an uncertain rollback stops egress instead of reporting success.</p>
    <p><strong>Scope:</strong> this is <em>deny → approve → retry</em>, not “pause the original connection.” <code>revoke</code> affects new tunnels only and never overrides startup policy. Grants add no private-address trust and end with the run.</p>
    <p><strong>Strict mode takes no grants:</strong> its tool hosts are fixed at startup with <code>RAPUNZEL_EGRESS_ALLOW</code>, and a provider API host is refused there.</p>
  </div>
  <p class="intro">Decision records D14 and D17 in <a href="egress.md">docs/egress.md</a> hold the design; <code>./verify-control.sh</code> tests grants through the real launcher and the pinned Pipelock.</p>
</section>

<section id="code" aria-labelledby="code-heading">
  <div class="section-heading"><span class="section-number">07</span><h2 id="code-heading">Follow the concepts into the code.</h2></div>
  <div class="source-map">
    <a href="../rapunzel">rapunzel<span>Host launcher: inputs, environment policy, container arguments, cleanup.</span></a>
    <a href="../lib/egress.sh">lib/egress.sh<span>Networks, sidecars, allowlist rendering, credential gateway, stale-resource sweep.</span></a>
    <a href="../lib/host-files.sh">lib/host-files.sh<span>Pinned <code>.git</code>, read-only git mounts, and host-executed-file change reporting.</span></a>
    <a href="../lib/policy.sh">lib/policy.sh<span>Startup allowlist and its reasons, shared by the launcher and the config report.</span></a>
    <a href="../rapunzel-ctl">rapunzel-ctl, lib/control.sh<span>Run discovery, blocked events, and confirmed runtime grants.</span></a>
    <a href="../lib/workspace.sh">lib/workspace.sh<span>Clone workspace: history in and out as checked git bundles.</span></a>
    <a href="../lib/volumes.sh">lib/volumes.sh<span>Project–harness volume naming and runtime ownership.</span></a>
    <a href="../Dockerfile">Dockerfile<span>Shared base, separate harness image stages, fixed entrypoint.</span></a>
    <a href="../profiles/">profiles/&lt;name&gt;/<span>Data-only profile definitions and harness-specific bootstrapping.</span></a>
    <a href="architecture.md">docs/architecture.md<span>Full design, trust model, verification, and known limitations.</span></a>
    <a href="egress.md">docs/egress.md<span>Network decisions, rejected alternatives, attack evidence, and residual risks.</span></a>
    <a href="guide.md">docs/guide.md<span>Commands, provider setup, login flows, and configuration examples.</span></a>
    <a href="https://github.com/pipelab-org/pipelock/blob/v3.7.1/docs/configuration.md#hot-reload">Pipelock 3.7.1: hot reload<span>Upstream reference for the reload that runtime grants use.</span></a>
  </div>
  <p class="footer">A static architectural snapshot of this checkout, 24 October 2026. Self-contained HTML: no external fonts, scripts, images, or network requests. Companion source: <a href="concepts.md">concepts.md</a>.</p>
</section>
</div>
