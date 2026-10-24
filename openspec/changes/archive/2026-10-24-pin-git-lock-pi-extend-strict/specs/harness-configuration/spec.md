## MODIFIED Requirements

### Requirement: pi gateway overrides

In strict mode the pi bootstrap SHALL point each built-in provider listed in `RAPUNZEL_GATEWAY_PROVIDERS` at its gateway route (`anthropic` at `/anthropic`, `openai` at `/openai/v1`, `openrouter` at `/openrouter`, `google` at `/google/v1beta`, `groq` at `/groq/v1`, `mistral` at `/mistral`, `deepseek` at `/deepseek`, `xai` at `/xai/v1`) with the placeholder key `rapunzel-gateway`. In other modes it MUST remove such overrides left by an earlier strict run. When `auth.json` holds `/login` credentials in strict mode, it SHALL warn that the gateway cannot keep them out.

#### Scenario: Switching from strict back to open
- **WHEN** a project last ran in strict mode and now runs in open mode
- **THEN** the built-in provider entries no longer carry the gateway base URL or placeholder key

#### Scenario: Google key in strict mode
- **WHEN** pi starts in strict mode with `GEMINI_API_KEY` set on the host
- **THEN** pi's `google` provider uses `http://llm-proxy:8080/google/v1beta` with key `rapunzel-gateway`
