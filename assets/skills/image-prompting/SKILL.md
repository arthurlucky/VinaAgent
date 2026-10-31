---
name: image-prompting
description: Write strong prompts for the generate_image tool. Use whenever the user asks to create, draw, design, render, or edit an image, logo, wallpaper, or illustration.
triggers: [gambar, image, foto, ilustrasi, wallpaper, logo, lukis, draw]
---

# Image Prompting

## Prompt formula

`subject + composition + style + lighting + palette + detail level + aspect ratio`

Example: "A lone lighthouse on a basalt cliff, low-angle wide shot, cinematic
realism, cold blue-hour light with a warm lamp glow, muted teal and amber
palette, fine surface detail, 16:9".

## Workflow

1. Infer the intended use (wallpaper, icon, social post) and pick the aspect
   ratio. Default to 1:1 only when the use is unclear.
2. If the user gave a reference image, describe what to keep and what to change.
3. Expand the request into one vivid paragraph. Avoid vague words such as
   "beautiful" or "high quality".
4. Call `generate_image` once, then evaluate the result before regenerating.
5. On a retry, change **one** variable (composition, style, or lighting) and say
   what changed.

## Avoid

- Brand names, real people's likenesses, or copyrighted characters.
- More than about 60 words of prompt; long prompts dilute the subject.
- Asking the model to render text unless the tool is known to handle typography.
