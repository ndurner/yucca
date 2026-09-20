# README image provenance

- `iphone.png`: supplied `IMG_1740.PNG`, resized for the README; app content unchanged.
- `watch.png`: supplied Watch screenshot, unchanged.
- `watch-photo.jpg`: supplied `IMG_1763.HEIC`, retouched with the built-in ImageGen tool using the Watch screenshot, reframed in a second pass, and labeled in a third pass using the Commission's AI MODIFIED graphic as a reference. Exported as JPEG. The disclosure is embedded in the photo and included in the README's alt text. Original files in Downloads were left unchanged.

## AI disclosure label

The reference is the European Commission's **Partially AI-Modified** icon, available from [EU Icons for labelling AI-generated content](https://digital-strategy.ec.europa.eu/en/policies/eu-icons-labelling-ai-generated-content) (checked 20 September 2026). The Commission makes the icons freely available without attribution. The label in this photo was reproduced by ImageGen from that reference.

The Commission states that the icons are optional, that not all AI edits require disclosure, and that using an icon does not establish legal compliance by itself. Here it provides a concise disclosure of reflection removal and screen reconstruction, without asserting that this photo necessarily falls within the AI Act's deepfake definition or that the project is a Code of Practice signatory. The original iPhone and Watch screenshots have no AI label because their content was not AI-edited.

## Label prompt

The labeling pass used the built-in ImageGen tool with this prompt:

Use case: compositing. Image 1 is the edit target, the square Apple Watch photograph. Image 2 is the official EU AI MODIFIED label reference. Add ONLY the black rounded pill with the white text AI MODIFIED from image 2 (discard all surrounding white canvas). Match the exact pill design, typography and proportions faithfully. Place it as a flat graphic overlay at the bottom left of the photograph, inset 3% from the left and bottom edges, at 35% of the photograph width, approximately 7.6% of its height. This makes it readable when the image is shown at 420px wide. Preserve crisp text and solid black/white contrast, no transparency. Keep it wholly below the watch case on the tabletop/strap area, do not cover any watch screen or case. Preserve the exact square crop, camera angle, watch case and crown, strap, background, lighting, UI and all existing text and numbers (11:58, TODAY, WEEK, 00:00, 40:38, Enter) unchanged. No other changes, no new caption, no EU flag or seal. Return the complete labeled photograph.

## Retouch prompt

Use case: compositing. Asset type: GitHub README product photograph. Image 1 is the edit target: a real Apple Watch photograph. Image 2 is supporting screen content: the exact Yucca Watch screenshot. Remove the distracting reflection of the photographer/phone and ceiling from the watch glass, using image 2 to restore the screen cleanly and legibly with matching perspective. Preserve the original watch case, crown, strap, tabletop, camera angle, composition and realistic photographic texture. Only change the screen/glass reflection. Screen text must match image 2 verbatim: 11:58, TODAY, WEEK, 00:00, 40:38, Enter, with the up-right arrow and yellow circular button. Preserve all UI layout and typography from image 2. No added branding, objects, claims, labels or watermarks. Output upright portrait orientation.

## Crop prompt

Use case: precise-object-edit. Crop this retouched photograph more tightly around the Apple Watch for a GitHub README. Remove excess strap/tabletop above and below and the small skin sliver at the top left. Keep the entire case and crown, with a modest margin and small lengths of strap above and below. Output a near-square portrait crop. Preserve the photograph, perspective, materials, screen layout, exact typography and every displayed value unchanged: 11:58, TODAY, WEEK, 00:00, 40:38, Enter and the up-right arrow. No new objects, no new text, no redesign. This is a framing/cropping adjustment only.
