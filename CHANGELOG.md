# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html); on `0.y.z` anything may change.

## [Unreleased]

## [1.3.3] - 2026-10-19

### Changed

- The MCP endpoint runs on MCP SDK v2: tools register on `@modelcontextprotocol/server` 2.3.1 and each request gets a fresh server from a factory passed to `createMcpHandler` in `agents/mcp/server`, the replacement agents 0.28.1 names for its deprecated SDK v1 path. The same 9 tools, schemas and auth gate apply.
- The endpoint accepts browser requests carrying an `Origin` header from localhost and the Worker's own workers.dev hostname; server-side clients such as claude.ai and Claude Code send no `Origin` and connect as before.
- `@modelcontextprotocol/server` replaces `@modelcontextprotocol/sdk` as a direct dependency; agents still installs the SDK as its own peer.
- The Worker bundle is 1255.84 KiB, down from 3433.85 KiB, because the handler comes from the isolated `agents/mcp/server` entry point.

### Fixed

- `verify.sh` tests the claude.ai connector flow again: with `CONNECT_SECRET` in the environment it sends the connect key, then checks the OAuth token, a wrong connect key (401), a wrong PKCE verifier and a replayed code (both `invalid_grant`). Without it, the script checks that `/oauth/confirm` refuses a request without the key.
- `verify.sh` passes secrets to curl through a stdin config, so they stay off the process list, and reads tool counts from JSON or SSE responses.

## [1.3.2] - 2026-10-19

### Security

- MCP TypeScript SDK 1.32.1 and MCP client 2.3.1, which keep the OAuth client talking only to the intended authorization server ([GHSA-6qxp-vccf-f47h](https://github.com/advisories/GHSA-6qxp-vccf-f47h)).
- proxy-addr 2.0.8, which closes IP spoofing through an IPv4-mapped IPv6 trust subnet ([GHSA-jqcg-44mw-7w3h](https://github.com/advisories/GHSA-jqcg-44mw-7w3h)).
- Local development runtime: sharp 0.35.5 ([GHSA-wq5f-xc86-pv6w](https://github.com/advisories/GHSA-wq5f-xc86-pv6w)) and undici 7.29.1 (six advisories), both through wrangler. Neither ships in the deployed Worker.

### Changed

- agents 0.28.1, the first release that pairs with the patched MCP SDK and client.
- wrangler 4.149.0, the first release whose local runtime carries the patched sharp and undici.

## [1.3.1] - 2026-10-18

### Changed

- Description shortened to fit search cards.
- Punctuation in README, docs, manifest and comments uses no em dashes.

### Removed

- A working audit brief that was committed to the repository by mistake; briefs are now gitignored.

## [1.3.0] - 2026-09-20

### Added

- Single-use authorization codes backed by the `CodeLedger` Durable Object.
- Auth regression suite in `test/auth.test.ts`.
- Repository conventions: `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue and pull request templates, and CI.

### Fixed

- Hosted auth fixes backported to this server.

## [1.2.0] - 2026-07-23

### Added

- Inbound auth on the `/mcp` endpoint: a static `AUTH_SECRET` bearer for automation and Claude Code, and OAuth 2.0/PKCE with stateless HMAC tokens for the claude.ai connector.
- `AGENTS.md` install contract, `mcp.json` manifest, and `verify.sh`, an adversarial check that asserts an unauthenticated request is refused.
- `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`.

### Changed

- README documents the `AUTH_SECRET` setup step and both auth paths.

## [1.1.0] - 2026-05-13

### Added

- `grok_image_generate`, `grok_image_understand`, `grok_image_edit`, `grok_video_generate`, `grok_structured_output`, `grok_reasoning`.

### Changed

- Shared `xaiFetch` helper and separate response extractors for text, image, and video. All tools remain stateless.

## [1.0.0] - 2026-05-11

### Added

- Initial release: `x_search`, `grok_web_search`, `grok_chat` as MCP tools over a Cloudflare Worker. Stateless, no Durable Objects.
