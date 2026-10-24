import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

const configDir = process.argv[2];
if (!configDir) throw new Error("configuration directory is required");
await mkdir(configDir, { recursive: true });

const env = process.env;

async function readJson(file, fallback) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
}

async function writeJson(file, value) {
  await writeFile(file, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
}

// strict mode: Claude Code's documented LLM-gateway settings point it at the
// credential gateway with a placeholder; the gateway sends the real API key or
// subscription token upstream. They go into the env block of settings.json
// because that block overrides the process environment, so an entry left there
// earlier cannot redirect a strict run. The marker file records what was set,
// so a later run outside strict mode removes exactly those entries.
const gatewayUrl = env.RAPUNZEL_GATEWAY_URL?.trim();
const gatewayProviders = (env.RAPUNZEL_GATEWAY_PROVIDERS ?? "").split(",").map((name) => name.trim());
const gateway = Boolean(gatewayUrl) && gatewayProviders.includes("anthropic");
const gatewayKey = "rapunzel-gateway";
const credentialVariables = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"];
const settingsFile = join(configDir, "settings.json");
const markerFile = join(configDir, ".rapunzel-gateway.json");
const marker = await readJson(markerFile, null);

if (gateway || marker) {
  const settings = await readJson(settingsFile, {});
  settings.env ??= {};
  if (marker) {
    // Undo the previous strict run's entries unless they were changed since.
    for (const [name, value] of Object.entries(marker.env ?? {})) {
      if (settings.env[name] === value) delete settings.env[name];
    }
    if (marker.addedSkipWebFetchPreflight && settings.skipWebFetchPreflight === true) {
      delete settings.skipWebFetchPreflight;
    }
  }
  let next = null;
  if (gateway) {
    // A subscription token keeps Claude Code in OAuth mode, so it sends the
    // OAuth anthropic-beta value; an API key placeholder goes in
    // ANTHROPIC_AUTH_TOKEN, which needs no interactive approval.
    const tokenVariable =
      env.RAPUNZEL_GATEWAY_ANTHROPIC_AUTH === "oauth" ? "CLAUDE_CODE_OAUTH_TOKEN" : "ANTHROPIC_AUTH_TOKEN";
    for (const name of credentialVariables) {
      if (name in settings.env && settings.env[name] !== gatewayKey) {
        console.error(`rapunzel: removed ${name} from the env block of settings.json; strict mode keeps credentials at the gateway.`);
      }
      delete settings.env[name];
    }
    const entries = { ANTHROPIC_BASE_URL: `${gatewayUrl}/anthropic`, [tokenVariable]: gatewayKey };
    Object.assign(settings.env, entries);
    // The WebFetch domain preflight calls api.anthropic.com directly, which has
    // no route in strict mode; WebFetch itself has none either.
    const addedSkipWebFetchPreflight = settings.skipWebFetchPreflight !== true;
    settings.skipWebFetchPreflight = true;
    next = { env: entries, addedSkipWebFetchPreflight };
    if (settings.apiKeyHelper) {
      console.error(
        "rapunzel: settings.json sets apiKeyHelper, which replaces the gateway placeholder; requests may fail until it is removed.",
      );
    }
  }
  if (Object.keys(settings.env).length === 0) delete settings.env;
  await writeJson(settingsFile, settings);
  if (next) await writeJson(markerFile, next);
  else await rm(markerFile, { force: true });
}

if (gateway) {
  try {
    await stat(join(configDir, ".credentials.json"));
    console.error(
      "rapunzel: .credentials.json in the agent volume holds a /login session inside the sandbox; the gateway cannot keep it out. Run /logout to remove it.",
    );
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

// With a credential from the host (CLAUDE_CODE_OAUTH_TOKEN from
// `claude setup-token`, or ANTHROPIC_API_KEY) or the gateway, first-run
// onboarding would still ask for a login method. Mark onboarding done so the
// credential is used as is. Without one, leave onboarding alone so /login
// stays reachable.
if (gateway || env.CLAUDE_CODE_OAUTH_TOKEN?.trim() || env.ANTHROPIC_API_KEY?.trim()) {
  const file = join(configDir, ".claude.json");
  const state = await readJson(file, {});
  if (state.hasCompletedOnboarding !== true) {
    state.hasCompletedOnboarding = true;
    await writeJson(file, state);
  }
}
