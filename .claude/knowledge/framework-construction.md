# Framework Construction

This covers two levels in one place: **the loop across frameworks** (the order they get built,
one after another) and **the protocol for configuring a single one** (the detail of step 2 of
the loop). There isn't a separate document for each level.

Precondition: foundations resolved (see `tokenization.md` — Part A, with no gaps). If anything is
missing there, no framework is started.

## The loop, framework by framework

One at a time. Never in parallel, never in batch — each framework is closed (approved) before
opening the next.

1. **Choose which framework to build first.** The one with the highest piece volume, or the
   structurally simplest one — what gets learned (text-scaling curves, image behavior) carries
   over to the next ones.
2. **Configure this framework.** See the detailed protocol below.
3. **Explicit approval of the base document** (`drafts/<name>.md`, with its first size
   resolved) **and of its test piece**, then the approved version is saved in Decodex (steps 6
   and 7 of the protocol below). Nothing moves forward without this.
4. **Add variants**: fill in the B4 tables (content variants and product/color variants) inside
   the same document — nothing new is created, what was already anticipated gets filled in.
5. **Add sizes/buckets**: for each new B7 size, add its row to the B6 tables (exact measurements)
   inside the same document — the color roles, image mode, or text rules are never redeclared
   there; those are resolved once, in B1/B2/B5. A new size never defines a new framework; only a
   different composition does.
6. **Review edge cases**: longer-than-expected copy, a low-contrast variant, the bucket's
   narrowest size.
7. **Go back to step 1 for the next framework**, carrying what was learned as a starting point —
   not as a reset to zero.

## Configuration protocol for a single framework (detail of step 2)

Each framework is a mini-project: it has its own intent, objective, channels, and rules. The
result is **a single document**: drafted locally as `drafts/<name>.md` (the working draft)
and, once approved, saved in Decodex with `add_framework` (the approved version, see step 7).
Drafts never go in `frameworks/`: that folder is a frozen legacy baseline, synced once with
`decodex-sync` and then locked.

**No code is built at this layer.** The document, while it's being drafted together with the
brand expert, IS the complete specification. If something isn't in the document, it isn't
defined.

The names the document uses (roles, elements, tokens) always come from the naming convention in
`tokenization.md` — a loose name outside those families is never invented.

### 0. Entry point — is there a Figma file or not?

Two possible paths for the first size. Which one applies is asked explicitly — never assumed.

- **Path A — there is structure in Figma** (only offered when a Figma tool is connected).
  Geometry is extracted directly from the file. Even so, what each layer is gets confirmed with
  the brand expert before documenting it — Figma gives position, not always intent.
- **Path B — no Figma, only a reference image + description.** First, figure out what kind of
  reference it is: a finished example piece (already shows the full layout), or a loose asset
  (e.g. a cut-out product, with nothing composed around it)? If it's a loose asset, the full
  composition is NOT in the image — it gets confirmed with the brand expert separately, element
  by element, for whatever still needs to be composed, not just the asset itself. In both cases:
  before documenting, do exhaustive work, element by element — list every visual element, confirm
  with the brand expert what it is, its approximate position, and its behavior. Don't move
  forward until every element is confirmed — an image can be misread, and that error propagates
  into everything documented on top of it.

  **Measure, don't eyeball.** Once the elements are confirmed, measure the reference with
  `measure_reference.py` (see `decodex-render-pipeline`): `--palette` for its dominant colors,
  `--probe X,Y` for the exact color of one element, `--box X0,Y0,X1,Y1` for the bounding box of
  the element inside that region. The script also reports each box as a proportion of the
  canvas: that proportion, not the pixel value, is what goes into B5 (sizes as % of canvas
  width) and B6 (positions as % of canvas width/height). The sampled colors feed the palette
  check before B1.

### 1. Intent, objective, and channels (B0)

Defined before touching structure or rules, one at a time, in the document's first section
(these apply to the whole framework, not just the first size):

- **Intent** — why does this framework exist in the communication strategy?
- **Objective** — what must a piece from this framework concretely achieve?
- **Channels** — which channels does it run on? This determines which sizes (B7) need to be
  documented — listed in step 2.7 and filled in one at a time in step 5 of the macro loop.

### 2. Draft `drafts/<name>.md`, section by section

In this order, one part at a time. Don't move to the next without closing the previous one. Each
answer is written directly into the document as it comes — answers aren't stockpiled to
transcribe everything at the end:

1. **Color roles** (B1 of `tokenization.md`). Before the first role, check the palette: compare
   the reference's colors (sampled in step 0) with `get_brand_colors`. A color that isn't saved
   is offered to the brand expert to save with `set_brand_color` — Codifier only, and only after
   a clear yes, because it changes the shared brand. Each role then points to the palette slug
   exactly as `get_brand_colors` returns it (e.g. `azul-spam`), never to a raw hex — a framework
   written with hardcoded hex is out of sync with the brand from day one.
2. **Image mode** (B2) and its cropping/framing rules.
3. **Complete element list** (B3) — EVERYTHING that makes up the framework, dynamic or fixed,
   drawn from path A or B of step 0. This is resolved before variants, because variants are
   described in terms of which elements change. This list is also the contract for any
   bulk-copy brief (spreadsheet, feed, etc.) — see the note at the end of B3 in
   `tokenization.md`.
4. **Variants** (B4) — content and/or product/color, always as a variation of components over
   the same composition.
5. **Typography and text-scaling rules** (B5), with character caps as explicit values. Check
   that every weight the table needs is stored: `get_brand_fonts` lists the weights of each
   uploaded family. A missing weight is offered for upload (`decodex-asset-upload`, "Fonts") or
   recorded in the document as pending — a font or weight is never silently swapped.
6. **Exact measurements of the first size** (B6) — position, distance, margins, radii,
   elevation/shadow, and stroke for EVERY B3 element. Nothing eyeballed: measured with
   `measure_reference.py` (step 0) or taken from Figma.
7. **Sizes/buckets covered** (B7) — list which other sizes the framework will need (added one at
   a time later, in step 5 of the macro loop).
8. **Assets** (B8).
9. **Special behaviors** → if it applies to every size, it goes next to the corresponding general
   rule; if it's specific to one size, it goes in that size's row in B6. Never a hidden special
   case left unexplained.

### 3. Request assets

Once the configuration makes clear what's needed, it's requested explicitly. Assets are shared
across ALL sizes of this framework — they aren't requested again per size. The document
references them by file name, never duplicates them.

Every B8 asset (e.g. the product cutout) is uploaded with `decodex-asset-upload` before the test
piece, and the test piece uses its local copy in `library/`. In product mode (B2), a file with a
baked-in background is still usable for the test, but the document records "pending: clean
cutout" until a clean one arrives.

### 4. Continuous verification

Each section, as it's drafted, is reviewed with the brand expert against the reference (Figma or
image) — the first review doesn't wait for the whole document to be ready. If something had to
be assumed because it wasn't confirmed, that gets flagged explicitly to the brand expert — never
silently, and documentation never continues on top of an unconfirmed assumption. As an
additional sanity check: B6 measurements must be internally consistent and consistent against
the canvas size (do the widths and positions fit inside the canvas? does the margin leave room
for the longest copy allowed in B5?).

### 5. Polish with the brand expert

The brand expert corrects based on what they see in the document. If the correction is to
something shared across all sizes (B1, B2, B3, B4, B5), it's corrected in that section; if it's a
size-specific measurement (B6), it's corrected in that size's row. Telling these apart on every
correction is what prevents the same rule from ending up written differently in two places of
the same document.

### 6. Approval

Before approving, confirm the document meets the objective declared in step 1 (B0) — a tidy
specification that doesn't meet what B0 asked for isn't approved. The order that closes a
framework:

1. Every section (B0–B8) approved one at a time, as drafted (step 2).
2. A test piece of the first size, rendered with `decodex-render-pipeline` and opened for the
   brand expert.
3. Explicit approval over the complete document and the test piece.
4. Saved in Decodex with `add_framework` (step 7), then verified (step 8).

Then → back to step 3 of the macro loop.

### 7. Save the approved version in Decodex

`add_framework(name, specMarkdown, slots[], manifest)`. `specMarkdown` is the approved document.
Each slot is typed by `kind` and named by its token:

| From the document | Slot `kind` | Slot `name` | Resolved by |
|---|---|---|---|
| Each B1 role | `color` | its role token (`color.role.background.primary`) | `colorSlug`: the palette slug, resolved live |
| Each B5 family | `font` | its family token (`font.family.display`) | `fontRole`: `primary`, `secondary`, `body` or `heading`, resolved live |
| Each dynamic B3 element | `text`, `image` or `logo` | its element token | `description`, including its character cap for text |
| Anything else the composition needs | `other` | its token | `description` |

`isDynamic` mirrors the B3 "Dynamic or fixed?" column. `manifest.description` is one line — it's
what `list_frameworks` shows; the manifest also carries the sizes (B7), buckets and variants (B4).

### 8. Verify

`list_frameworks` shows the framework with its one-line description, and `get_framework` shows
each color and font slot resolved live (e.g. "#043673 (Azul SPAM)"). A slot that doesn't resolve
means a wrong slug or role: fix it before moving on. From here, `drafts/<name>.md` stays as
the local working draft; Decodex holds the approved version.

## Keeping the framework document in sync with the engine

Once `engine/` implements this framework (see `engine-principles.md`), the build may need to
diverge from what this document currently says — a value that looked right on paper doesn't
render well, or a rule needs correcting once real content is tested against it. That is allowed.
What is not allowed is the divergence living only inside the engine:

- The reason for the change is documented as a comment at the point in the engine code where the
  deviation happens — that part doesn't move.
- The corresponding field in `drafts/<name>.md` (when there is no draft, start one from the
  approved `get_framework` spec) is updated to the new, true value or rule, in the same pass. Once the change is approved, save it again with `add_framework` under the same
  name: it overwrites the previous version and its whole slot list, so send every slot again.
  The document is the specification; if the engine and the document disagree, the document has
  silently stopped being true.

`drafts/<name>.md` is not only written before the engine exists — it keeps getting corrected
after, every time reality reveals it was wrong.

## Signs something is being invented (stop if one appears)

The method's general anti-hallucination rules always apply here too. Three signals specific to
this loop:

- Copy is being drafted while the brand's tone/legal foundations aren't resolved yet.
- A raw hex is written into B1, or a B5/B6 value is estimated by eye instead of measured.
- A new size (B6) is being added and it's used as an opportunity to redefine a color role, the
  image mode, or a text rule "just for this size" — those rules belong to the whole framework
  (B1, B2, B5), not to one size; if they truly change per size, that's a special behavior and
  gets documented as one, not silently.
