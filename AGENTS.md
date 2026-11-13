Read docs/internal/CONTRACT.md before doing anything, if it is present in your checkout. It is the source of truth.
This repository is PUBLIC. Never commit secrets, .env files, keys, voice IDs, docs/internal/, .cache/, audio recordings, personal details, or unlicensed assets. Keep commit messages, comments and copy professional. Never present sample or unmeasured numbers as real. Read git diff --cached before every commit. If a secret is committed, stop and tell the human at once.
You own only the paths listed in your task. Never edit any other path, including package.json.
If you need a change outside your paths, stop and say so in your final message.
Develop with NEXT_PUBLIC_MOCK=1 unless your task says you own a live integration.
Never start `next dev` on port 3000 inside a worktree; use PORT=31xx.
Before you finish: npm run check must pass. Commit with a clear message. Do not push to main.
Prefer the simplest thing that makes the demo path reliable and beautiful. No generality.
Kid-facing copy: warm, short, never a grade. No em dashes in any copy.

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
