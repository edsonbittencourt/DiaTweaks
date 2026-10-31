# Contributing

Keep it small, test it hard, show it working.

## Pull requests

- One change per PR.
- Fill in the template: What, Why, Proof, Tested on, Checklist. Short sentences.
- Proof is required for anything visible in Dia: a screenshot for static changes, a screen recording for anything that animates. Show before and after when you change existing behaviour.
- Try to break what you made before you open the PR, and fix what you find. Every change has to work with tabs in the sidebar and tabs at the top, and with each tweak on and off.
- Build with `make` and run it on your own Dia with `./install.sh`.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org): `fix(dylib): keep the top padding under horizontal tabs`.
- Imperative, lowercase, under 72 characters. Add a body only if the diff would mislead without it.
- No tool or AI attribution trailers (`Co-authored-by: Claude`, `Generated with …`).

## AI tools

Use whatever tools you like. You're responsible for what you submit: it has to work, and you have to have tested it yourself.

No slop: no padded descriptions, generated summaries or filler ("comprehensive", "robust", "seamless", "this PR introduces…"). PRs that read like unchecked AI output are closed without review.

## Never

- Commit Dia itself or anything from its bundle.
- Sign with, or ship, anyone else's certificate.
