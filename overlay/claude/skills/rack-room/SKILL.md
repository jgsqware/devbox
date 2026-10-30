---
name: rack-room
description: The "rack room" design system for HTML pages and artifacts — technical, datacenter-panel look (Big Shoulders Display + IBM Plex, slate/teal/amber tokens, light and dark), with components for cards, tabs, status pills, command lines, numbered steps, nested layers, animated SVG bus diagrams and hover-term tooltips. Use when the user asks for the "rack room" look/style/design system, wants a page "like the repo map", or when another skill (e.g. repo-map) says to apply it.
---

# Rack room design system

A dense, technical look: a lit control panel in a server room. Slate backgrounds, one teal accent for technical things, one amber accent for business things, condensed uppercase display headings, mono labels everywhere data lives.

Apply it exactly. Start from `tokens.css` (next to this file): paste it into the page's `<style>`, then build on the classes it defines. Load the artifact tooling as usual (quickstart / artifact-design) when publishing an artifact; this skill only replaces the visual choices.

## 1. Foundations

- **Fonts** (Google Fonts):
  - display: "Big Shoulders Display" 600/800, UPPERCASE h1/h2 only, line-height about 1;
  - body: "IBM Plex Sans" 400/500/600;
  - mono: "IBM Plex Mono" 400/500 for labels, eyebrows, paths, chips, pills and diagram text.
  - Always give fallback stacks (see `tokens.css`).
- **Colors**: only the tokens below, never raw hex in components.

  | Token | Light | Dark | Use |
  |---|---|---|---|
  | `--bg` | `#ECEFF1` | `#0E161C` | page background |
  | `--surface` | `#FFFFFF` | `#15212A` | cards, boxes |
  | `--ink` | `#15232D` | `#E3EAEE` | text, wires |
  | `--muted` | `#586A76` | `#8DA0AC` | secondary text |
  | `--line` | `#C6D0D7` | `#283944` | borders, box strokes |
  | `--teal` | `#0F6E7D` | `#4DB4C4` | technical / network / primary accent |
  | `--amber` | `#B8600C` | `#F0A04B` | business / shares / images / prompts |
  | `--ok` | `#2A7A4B` | `#5DC28C` | done, exists |
  | `--warn` | `#9A6200` | `#E2B24E` | to do, partial |
  | `--bad` | `#B23A3A` | `#E58A8A` | missing, failing |
  | `--code-bg` | `#15232D` | `#0A1015` | command blocks, tooltips |
  | `--code-fg` | `#DDE6EB` | `#DDE6EB` | text on code-bg |

  Dark tokens go under both `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) }` and `:root[data-theme="dark"]`. `body` has an explicit `background: var(--bg)`.
- **Type scale**: body 13.5px; h1 `clamp(36px,5.5vw,64px)`; h2 `clamp(24px,3.2vw,34px)`; eyebrows 11px mono uppercase, letter-spacing .12em, teal.
- **Layout**: wide container (max-width about 1520px), 16px side gutters on mobile, no horizontal page scroll. Cards: `--surface`, 1px `--line` border, 8px radius, no heavy shadows.

## 2. Components

- **Tab bar**: sticky at the top, routed on `#hash` with plain names (`#layers`). Mono uppercase tabs; the active one gets a teal underline. An optional filter box filters every tab.
- **List + sticky detail**: clickable list grouped by tier on the left, sticky detail panel on the right (stacked on mobile). Callouts inside the panel: left border teal (technical) or amber (business).
- **Chips**: mono, small, 1px line border, 4px radius; a selected filter chip is filled teal with surface text.
- **Status pills**: mono uppercase, 1px `currentColor` border, color `--ok` / `--warn` / `--bad`.
- **Command line**: `--code-bg` block, `--code-fg` text, an amber `$ ` prompt (or `✎ ` before a file path), a copy button.
- **Numbered steps** (`ol.pipe`, CSS vars `--n` = columns, `--start` = counter offset): numbered circles joined by a line, lit teal one by one about 420 ms apart when the section opens, a "Replay the steps" button, a mono "who" label per step (teal / amber / muted). Vertical on mobile.
- **Nested layers**: boxes inside boxes with mono uppercase labels and chips (e.g. Terraform > Argo CD > clusters).
- **Matrix**: rows × columns grid; a filled cell (teal tint) means it exists, an empty cell is a faint dot. Clicking a cell shows and copies its value.
- **Progress bar**: 6px track in `--line`, fill in `--ok`, mono percentage label.

## 3. SVG bus diagrams

- viewBox about 820 wide, wrapped in `overflow-x:auto` with `min-width: 660px` on the SVG.
- **Boxes**: fill `--surface`, stroke `--line`, rx 6. Hub box tinted teal, special box tinted amber, inactive box dashed (`stroke-dasharray: 4 3`).
- **Bus**: thick teal line (stroke-width 5, round caps) with uppercase mono captions.
- **Wires**: `--ink`, 1.25px; flows dashed.
- **Animated packets**: `<circle r="4">` + `<animateMotion>` along a wire path, colored by meaning (teal technical, amber business, ok/bad for status).
- **Legend**: a row of colored dots with mono labels under each diagram.
- **Text fits its box**: about 8.4px per char at 14px mono, 6.3px per char at 10.5px. Check widths before placing text.
- Use the CSS variables in `fill` / `stroke` (via classes or `style`) so diagrams follow the theme.

## 4. Hover terms (optional, for explainer pages)

- A `TERMS` list (about 25–35 entries: `key`, `regex`, kind `biz` or `tech`, a 1–3 sentence explanation, optional `path`).
- A TreeWalker wraps the first occurrence per section; skip `code`, `pre`, `svg`, headings, buttons, nav, chips and pills.
- Dotted underline: teal = technical, amber = business. Add a small legend for the two colors.
- Tooltip: dark (`--code-bg`), fixed position, a "Technical" / "Business" badge and an optional "↳ path" line; opens on hover, focus and tap; hides on scroll.
- A MutationObserver (guarded against its own changes) re-annotates content rendered later.

## 5. Behavior rules

- Respect `prefers-reduced-motion`: hide packets, no transitions or step animation.
- Wrap every `localStorage` call in try/catch; the page must work without it.
- Copy buttons give feedback ("Copied") for about 1.2 s.
- Keyboard: tabs, list items and matrix cells are focusable buttons with a visible teal focus ring.
