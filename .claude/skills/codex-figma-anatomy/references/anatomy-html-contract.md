# Anatomy HTML Contract

The HTML is a generated, inspectable geometry record for one selected Figma frame. It is not a styled reproduction and is not the canonical framework specification.

## Required data

Embed one JSON object in `<script type="application/json" id="figma-anatomy-data">`. The object must contain:

- `source`: selected node ID, source URL, the coordinate space returned by MCP, the normalized coordinate space used by the renderer (`parent-relative`), and the visibility policy (`exclude-explicit-hidden; assume-visible-if-unspecified`). Include the file key when it is available from the link or MCP response.
- `frame`: original node ID/name, source `x`/`y` when supplied, width, height, and ordered `children`.
- Each included node: original `id`, `name`, `type`, raw MCP `sourceX`/`sourceY`, normalized parent-relative `x`/`y`, `width`, `height`, `visible: true`, `visibilityEvidence` (`mcp-explicit-visible` or `assumed-visible`), exact `text` when applicable, and recursively ordered `children`.

Use only values returned by Figma MCP for source values. Keep node names unchanged. Omit nodes explicitly marked hidden and image bytes. When visibility is absent, follow the agreed fallback: include the returned node and mark it `assumed-visible`; do not represent that assumption as an MCP fact. If required geometry or text is missing, do not generate a purportedly complete anatomy file.

## Rendering

Render the JSON into a visible, frame-sized `<main>` inside a responsive preview shell. By default, render at 1:1 CSS-pixel scale: the frame's CSS width and height must equal the Figma dimensions exactly, and its full extent must remain accessible by page scrolling on smaller viewports. Do not automatically shrink the frame to fit the viewport. If a zoom control is added, make it explicit and keep the natural Figma dimensions visible separately from the current preview zoom. Never change JSON or node geometry to fit the screen. Give the frame a visible boundary and neutral preview surface so its true extent is apparent. Center text inside each recorded text box horizontally and vertically, preserving its exact content and explicit line breaks. Show image slots as labeled placeholders, never image pixels. Use a restrained, friendly annotation palette for the preview shell and slot types; clearly treat these colors as viewer UI, not colors or fills extracted from Figma. Labels must not affect source geometry or layout positions.

The renderer must derive all displayed geometry from the embedded JSON so a future Python tool can parse one machine-readable source without scraping CSS. Escape text and attribute values for HTML; preserve Unicode and explicit newlines.

## Minimal renderer shape

Use a standalone document with no external dependencies. Keep the JSON as the single data source and create visible elements with DOM APIs and `textContent`—never interpolate Figma copy into executable JavaScript or HTML markup.

```html
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; min-height: 100%; }
  body { padding: 32px; background: #080808; color: #F5F5F5; font-family: "Mulish", sans-serif; }
  #stage { width: 100%; overflow: auto; }
  #frame { position: relative; flex: none; overflow: hidden; border: 1px solid #4361EF; background: #0D0D0D; }
  .node { position: absolute; }
  .node-body { position: absolute; inset: 0; display: grid; place-items: center; text-align: center; }
  .node--text .node-body { white-space: pre-line; overflow: hidden; }
  .node--image .node-body { background: #131313; color: #8C8C8C; }
  .node--headline .node-body { background: rgba(67,97,239,0.15); color: #F5F5F5; font: 700 60px/62px "Mulish", sans-serif; }
  .node--legal .node-body { background: rgba(255,255,255,0.05); color: #F5F5F5; font: 500 12px/14px "Mulish", sans-serif; }
  .node-label { position: absolute; left: 0; top: 0; transform: translateY(-100%); padding: 4px 8px; border-radius: 4px; background: #4361EF; color: #FFFFFF; font: 500 10px/12px "Mulish", sans-serif; white-space: nowrap; }
</style>
<header id="frame-heading"></header>
<div id="stage"><main id="frame"></main></div>
<script type="application/json" id="figma-anatomy-data">
{"source":{"fileKey":"FILE_KEY","nodeId":"1:2","url":"FIGMA_URL","sourceCoordinateSpace":"parent-relative","renderCoordinateSpace":"parent-relative","visibilityPolicy":"exclude-explicit-hidden; assume-visible-if-unspecified"},"frame":{"id":"1:2","name":"Square Ad","sourceX":0,"sourceY":0,"width":1080,"height":1080,"children":[{"id":"1:3","name":"Headline","type":"TEXT","sourceX":120,"sourceY":200,"x":120,"y":200,"width":840,"height":120,"visible":true,"visibilityEvidence":"assumed-visible","text":"Original headline","children":[]}]}}
</script>
<script>
  const data = JSON.parse(document.querySelector("#figma-anatomy-data").textContent);
  const frame = document.querySelector("#frame");
  const stage = document.querySelector("#stage");
  document.querySelector("#frame-heading").textContent =
    `${data.frame.name} · ${data.frame.width} × ${data.frame.height}`;
  frame.style.width = `${data.frame.width}px`; // Natural frame width from Figma data.
  frame.style.height = `${data.frame.height}px`; // Natural frame height from Figma data.

  function render(node) {
    const element = document.createElement("div");
    const name = node.name.toLowerCase();
    const isImage = node.type.toLowerCase() === "image" || name.startsWith("img_");
    const role = name.includes("headline") ? "headline" : name.includes("legal") ? "legal" : "other";
    element.className = `node ${isImage ? "node--image" : node.text == null ? "node--shape" : "node--text"} node--${role}`;
    element.dataset.figmaNodeId = node.id;
    element.dataset.figmaName = node.name;
    element.dataset.figmaType = node.type;
    Object.assign(element.style, {
      left: `${node.x}px`, top: `${node.y}px`,
      width: `${node.width}px`, height: `${node.height}px`,
    });
    const body = document.createElement("div");
    body.className = "node-body";
    if (node.text != null) body.textContent = node.text;
    else if (isImage) body.textContent = "Image";
    element.append(body);
    const label = document.createElement("span");
    label.className = "node-label";
    label.textContent = `${node.name} (${node.id})`;
    element.append(label);
    for (const child of node.children ?? []) element.append(render(child));
    return element;
  }

  for (const node of data.frame.children) frame.append(render(node));
</script>
```

Color values in the example describe the anatomy viewer UI only; they are not Figma properties. In repository-generated output, use the project's chosen viewer tokens and cite their source inline. Keep source geometry separate from presentation CSS.

Do not assume the coordinate space: Figma's public MCP tool reference documents that metadata includes positions and sizes, but does not specify whether positions are parent-relative or absolute. Preserve raw values as `sourceX`/`sourceY`; normalize to the renderer's parent-relative `x`/`y` only when their source space and the relevant parent/frame origins are explicit. Exact subtraction is acceptable, estimation is not. Record both spaces under `source`. If the MCP response does not make the coordinate space clear enough to render unambiguously, stop and report the gap. Escape `<` inside the JSON payload (for example as `\u003c`) so layer text cannot terminate the data script element.
