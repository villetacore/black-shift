# ImageGen prompts

Generated with the built-in ImageGen tool on 2026-10-16. No reference material from third-party games was supplied. The atlas was corrected in a second edit to match engine material indices.

## Atlas — initial generation

Use case: stylized-concept. Production game texture atlas for BLACK SHIFT, a late-1990s industrial military FPS. Generate a square 2048x2048 image, exactly 4 columns by 4 rows of equally sized square seamless diffuse material tiles, edge to edge, no gaps, no labels, no text, no perspective or objects or cast shadows. Every tile must fill exactly its quarter width and quarter height. Row 1: grey concrete floor slabs; grey concrete block wall; aged bronze riveted metal panels; muted yellow black industrial hazard panel. Row 2: dark olive woven military cloth; olive armored plate; brushed dark gunmetal; smoked teal visor glass. Row 3: neutral pale luminous mesh grille; worn ochre painted metal; charcoal rubber grip; dark steel panels. Row 4: ceiling metal coffers; rusty reddish pipe metal surface; warm white fluorescent diffuser; brown leather. Hand-painted tactile game textures, readable medium scale shapes, subtle scratches, restrained grime, believable manufactured detail, no photoreal noise, flat neutral illumination. Precise regular 4x4 atlas alignment is essential.

## Atlas — final correction

Edit this exact atlas: preserve style and exact equal 4x4 grid and all other cells. Correct the material order to match engine indices. Row 2 column 4 MUST be brown leather, not glass. Row 3 column 4 MUST be smoked teal visor glass. Row 4 column 1 MUST be dark steel plate. Row 4 column 2 MUST be ceiling metal coffers. Row 4 column 3 MUST be rusty pipe metal. Row 4 column 4 MUST be warm white fluorescent diffuser. All tiles flat front-on diffuse textures, no text, no gaps. Remaining ten cells unchanged.

Output: `assets/textures/foundry-materials-v2.png`.

## README cover

Use case: ads-marketing. Asset: wide cinematic open source videogame README cover, landscape 3:1. BLACK SHIFT is a low-poly late-1990s industrial team FPS about rotating relay control. Design a sophisticated dark charcoal editorial game banner with an angular cyan broken-square relay emblem and large impeccably legible condensed ivory title 'BLACK SHIFT' on the left, small subtitle 'RELAY CONFLICT' under it. On the right: atmospheric illustrated industrial foundry, overhead catwalks, steam, cables, cyan glowing relay ring and a small amber glow in the far distance. Restrained amber hazard stripe accents, subtle print grain, retro PC game box-art influence, premium carefully balanced typography. Keep text within safe margins. No screenshots, no photorealistic soldiers, no unrelated text, no badges, no watermark. This is clearly illustrative key art, not a gameplay screenshot.

Output: `docs/images/cover.png`.



## Industrial materials v3 — 17 October 2026

Built-in ImageGen; saved as `assets/textures/industrial-materials-v3.png`. Original request:

```text
Use case: stylized-concept. Production diffuse material atlas for BLACK SHIFT industrial retro FPS. Square 2048 x 2048 image, EXACT regular 4x4 grid of sixteen equal square tiles, edge to edge no margins no gaps no labels. Orthographic flat surface textures only, no objects, no perspective, no directional shadows. Late 1990s hand painted game textures, medium scale readable patterns, subtle wear. All surfaces individually tileable. Row 1 left to right: blue-grey powder coated machine panels; cream ceramic wall tiles; red painted industrial steel; green oxidized copper. Row 2: grey diamond tread steel; tightly spaced horizontal radiator fins; beige canvas tarp; dark oily rubber conveyor belt. Row 3: ivory instrument dial panel with small analogue gauges (no readable words); dark CRT circuit board with cyan traces; red and white diagonal safety stripes; dark steel wire mesh. Row 4: galvanized corrugated metal; warm orange electrical insulation; dark grey ribbed hose material; blue enamel technical panel with pale geometric arrows (no text). Restrained industrial palette, mostly matte material, neutral even lighting. Exact uniform square grid alignment crucial.
```
