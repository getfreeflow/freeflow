# FreeFlow landing page — plan

## The core idea

Most dev-tool landing pages show a screenshot and a feature list. The thing that makes
FreeFlow worth using isn't visible in a screenshot: it's the *transformation* between what
you say and what lands on screen. Nobody demonstrates that. That's the whole site.

**The device: the page is dictated into existence.**

The FreeFlow pill — the real one, same geometry, same waveform maths as
`RecordingHUD.swift` — sits pinned to the bottom of the viewport for the entire page, exactly
where it sits on a real Mac. It isn't a screenshot. It's live, it reacts to scroll position,
and it narrates each section. The site's furniture *is* the product.

That's the hook, and it's not a hook you can get from a template.

## Where it lives

`freeflow.github.io` is unavailable: `freeflow` and `freeflowapp` are both taken GitHub
accounts, and that URL requires owning the account of that name.

**Recommended:** `docs/` folder on `main` in the existing repo → serves at
`getfreeflow.github.io/freeflow`. Zero new infrastructure, one settings toggle, the
site lives beside the code it documents and ships in the same commit.

**Alternative:** create an org named `getfreeflow` (verified available) → `getfreeflow.github.io`.
Cleaner URL, more moving parts. Either can point at a real domain later.

## Stack

No build step. GitHub Pages serves the folder directly, so the repo stays clean and there's
no CI to break.

- Plain HTML + CSS + JS
- GSAP 3 + ScrollTrigger (CDN) for scroll choreography
- Lucide icons — inline SVG sprite, no emoji as icons (skill rule §4 `no-emoji-icons`)
- Two Google Fonts, `font-display: swap`
- Canvas for the waveform, reusing the app's actual sine composition

## Design direction

Taken from the reference (moveapp.dev) but not copied from it.

| | |
|---|---|
| Ground | Near-white with a cool cast, `#FAFAF9` → dark sections for contrast punctuation |
| Ink | `#0A0A0A` headline, `#525252` body |
| Accent | One only. Warm signal-orange `#FF4D00` against the neutral, rather than the reference's violet — it reads as "recording", which is what the product does |
| Type | Display: Instrument Sans or Geist (tight, technical). Body: same family, lighter weight. Mono: JetBrains Mono for the terminal |
| Rhythm | 8px scale, `max-w-6xl` container, generous vertical spacing (96/128/160) |

Two-tone headlines like the reference (black line, accent line). Tiny uppercase
letter-spaced eyebrows. Numbered steps. Product shots in rounded cards on a soft gradient.

## Sections

**1. Hero.** Headline writes itself word by word, as if dictated, with the pill live at the
bottom and its bars actually moving. Subhead. Two CTAs: a click-to-copy install command, and
GitHub. No signup, no email capture — there's nothing to sign up for, and pretending
otherwise would be the fakest thing on the page.

**2. The bottleneck.** Short declarative fragments. Speaking is ~3x typing. Raw speech-to-text
is unsendable. The gap between those two facts is the product.

**3. The demo — the centrepiece.** Pinned scroll section. A fake macOS compose box. A cursor
travels in, the pill wakes, bars move, and *raw* transcript streams in with every "um" and
false start. Then the cleanup pass runs and the text rewrites itself into something you'd
actually send. That before/after rewrite in place is the single most persuasive thing this
site can show, and no competitor shows it.

**4. Everything it does.** Nine features, Lucide icons, real screenshots. Staggered reveal
(30–50ms per item, skill rule §7 `stagger-sequence`).

**5. Nothing leaves your Mac.** The pipeline diagram from the README, animated as a signal
travelling through it, stopping dead at the boundary of the machine. The strongest honest
claim the product has.

**6. Install.** Interactive terminal. Tabbed steps, real commands, copy buttons, and a
faked-but-accurate output stream. Honest about the build-from-source requirement rather than
hiding it.

**7. FAQ.** The questions people will actually ask: is it really free, does it work offline,
why no download, does it send my voice anywhere.

**8. Footer.** MIT, unaffiliated disclaimer, repo link.

## Copy voice

Short. Declarative. Fragments where they land harder. First person where it's honest. No
"seamlessly", no "empower", no "revolutionize", no three-adjective stacks, no em-dashes.
Written like a person who built the thing explaining why, not like a company.

## Images

**Real screenshots are the primary visual.** Captured window-scoped from the running app,
never full-screen. For a developer tool, generated art actively reads as AI slop and would
undercut the "doesn't look AI" goal. The reference site uses real product shots for exactly
this reason.

**Flux is worth it for:** the OG/Twitter share card, and possibly one abstract textural
backdrop behind the hero. Both are places where there's no real thing to photograph.

Needs a Cloudflare Workers AI token, which isn't on this machine.

## Accessibility (skill §1–§3, non-negotiable)

- Contrast ≥4.5:1 body, ≥3:1 large
- Visible focus rings, never removed
- `prefers-reduced-motion` disables all scroll choreography, content readable immediately
- Alt text on every screenshot
- Tap targets ≥44px
- `width`/`height` on images to hold layout (CLS < 0.1)
- Semantic headings h1→h3, no skips
- Keyboard-reachable terminal tabs

## Build order

1. Capture app screenshots, window-scoped
2. Static skeleton: HTML, tokens, type scale, responsive at 375/768/1280
3. Copywriting pass
4. Waveform canvas + pinned demo
5. GSAP scroll choreography
6. Terminal component
7. Reduced-motion, keyboard, contrast audit
8. Ship to `docs/`, enable Pages
