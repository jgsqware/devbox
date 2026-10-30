---
name: repo-map
description: Build an interactive "repo map" artifact for the current repository (layers/components, what-runs-where matrix, animated SVG flow diagrams, onboarding steps, meeting points and open items, how-to, glossary, hover snippets) in the "rack room" design system (rack-room skill), and optionally deploy it to GitLab Pages. Use when the user asks to map, explain or visualise a repo for newcomers, to turn a meeting transcript about a repo into a navigable page, or says "repo map" / "carte du repo".
---

# Repo map

Build an interactive "repo map" artifact for THIS repository, so a newcomer can navigate and understand it. All page copy is in English. Reply to the user in French.

## 1. Explore first (read-only)

- Read README, AGENTS.md / CLAUDE.md, CONTRIBUTING, docs/ (architecture, runbooks, ADRs), CI config (.gitlab-ci.yml / .github/workflows) and the top-level layout. Delegate a broad sweep to an Explore agent if the repo is large.
- Identify the repo's own structure: layers, modules, services, environments, accounts, pipelines, manifests/config sources, and how they relate (what depends on or reads from what).
- Build the "what runs where" matrix (units × targets: accounts / envs / clusters / regions) from the real folder structure, not guesses.
- Read `git log --oneline -40` for recent work and ticket IDs.
- If the user pasted meeting notes or a transcript: extract its points and open items, and link each one to where the repo implements it (path + what is there). Flag items with nothing in the repo.
- Only state facts seen in files. When something comes from docs rather than code, or lives outside the repo, say so on the page.

## 2. Page structure

Tabs routed on `#hash` (plain names, e.g. `#layers`), plus a filter box that filters every tab.

1. **Layers / Components**: clickable list grouped by tier, with a sticky detail panel (what it does, where it is deployed, files to open, "In the meeting" callout, "Good to know" callout).
2. **Matrix**: units × targets; a filled cell means it exists. Clicking a cell shows and copies its path. Group / value-stream filter chips.
3. **Flows**: SVG diagrams of how things connect (accounts/services, CI from merge request to deploy, deploy/GitOps chain, network), with a short status table for external links.
4. **Onboarding**: how a new app / service / consumer gets added, as numbered steps in phases ("Once" / "On every release"), plus "In this repo" / "Outside this repo" cards.
5. **Meeting** (only when notes were given): one card per point, with "In the repo".
6. **Open items**: checklist saved in localStorage, a status pill ("already in repo" / "to design" / "nothing found") and a "Where:" line, plus a progress bar.
7. **How to**: common tasks with copyable commands; repeat the repo's safety rules (e.g. never apply locally).
8. **Glossary**.

## 3. Design system

Apply the **rack-room** skill exactly (load it with the Skill tool and start from its `tokens.css`). On this page use all its components: sticky tab bar, list + sticky detail, matrix, SVG bus diagrams with animated packets, numbered steps, nested layers, command lines, status pills, progress bar and hover terms.

## 4. Deliver

- Load the artifact tooling as usual (quickstart / artifact-design), write the page in the scratchpad and publish it. Then tell the user, in French: the link, what each tab contains, and the caveats (what you inferred, what lives outside the repo).
- On a later change request, edit the same file and republish to the same URL.

## 5. GitLab Pages (only when asked)

On a new branch (never commit or push without asking):

- `docs/site/index.html`: a full standalone document (`<!doctype html>`, `<html lang="en">`, head with charset, viewport and description, plus a small CSS reset: `body{margin:0}`, `[hidden]{display:none!important}`, `img{max-width:100%}`), then the artifact's own `<title>`, fonts and styles, and the body.
- `docs/site/README.md`: says it is a hand-maintained snapshot, how to update it (the data arrays in the script), and that Pages must stay restricted.
- A `pages` job in `.gitlab-ci.yml`:

  ```yaml
  pages:
    stage: deploy
    image: alpine:3.20
    script:
      - mkdir -p public
      - cp -r docs/site/. public/
    artifacts:
      paths:
        - public
    rules:
      - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
        changes:
          - docs/site/**/*
  ```

- Follow the repo's own rules (CHANGELOG policy, lint, pre-commit; if a tool is missing, say so). Check the CI file still parses (it may hold several YAML documents and custom tags such as `!reference`).
- Remind the user to set Pages visibility to "Only project members" (Settings → General → Visibility → Pages), since the map exposes internal architecture.
