#!/usr/bin/env python3
"""
Duplicate Region Detection for Stitched Screenshots

Detects duplicate content regions in vertically-stitched long screenshots
caused by overlap estimation errors. Distinguishes true pixel-level
duplication from structurally similar repeating layouts (e.g. video grids).

Key insight: true duplicates have matching content in HIGH-DETAIL rows
(thumbnails, text), while structural similarity only matches in
LOW-DETAIL rows (backgrounds, separators). The discriminator is the
fraction of content-rich rows that pixel-match between the two positions.

Three-phase pipeline:
  Phase 1: Coarse offset discovery (downsampled 4x, center-cropped)
  Phase 2: Content-aware block matching (100px blocks, content-row analysis)
  Phase 3: Full-width validation & deduplication

Usage:
  python3 detect_duplicates.py <image_path> [--annotate] [--verbose]

Dependencies: numpy, PIL only.
"""

import argparse
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


# ── Constants ──────────────────────────────────────────────────────────────

DOWNSAMPLE_FACTOR = 4

# Phase 1: coarse scan
COARSE_BLOCK_H = 32         # downsampled px (128 original)
COARSE_SLIDE_STEP = 16
COARSE_OFFSET_STEP = 8      # 32px original
COARSE_MAD_THRESH = 4.0
COARSE_MIN_STD = 5.0
MIN_COARSE_MATCHES = 2
TOP_K_OFFSETS = 30

# Phase 2: content-aware fine matching
FINE_BLOCK_H = 100           # block height (original px)
FINE_BLOCK_STEP = 50         # sliding step
CONTENT_ROW_STD = 40.0       # row std threshold: captures thumbnails/images, not just text
CONTENT_ROW_MAD = 8.0        # per-row MAD threshold for "matching content row"
CONTENT_MATCH_FRAC = 0.55    # min fraction of content rows that must match
MIN_CONTENT_ROWS = 8         # min content rows in a block to be evaluable
BLANK_BLOCK_MAD = 2.0        # full-width MAD for "nearly identical" blocks
MERGE_GAP = 50               # merge blocks within this gap (px)
MIN_REGION_H = 150           # min region height

# Phase 3: validation
REGION_CONTENT_FRAC = 0.40   # min content-row match fraction for whole region
FULLWIDTH_MAD_CAP = 10.0     # reject if full-width MAD exceeds this
MIN_REGION_CONTENT_ROWS = 15 # min content rows in a validated region
MIN_REGION_ENTROPY = 1.0     # min entropy for validated region
CENTER_MATCH_FRAC = 0.35     # min center-only content-row match (filters sidebar-driven false positives)


def load_grayscale(path: str) -> np.ndarray:
    img = Image.open(path).convert("L")
    return np.array(img, dtype=np.float32)


def center_crop(arr: np.ndarray, left_frac: float = 0.15, right_frac: float = 0.85) -> np.ndarray:
    w = arr.shape[1]
    return arr[:, int(w * left_frac) : int(w * right_frac)]


def downsample(arr: np.ndarray, factor: int) -> np.ndarray:
    h, w = arr.shape
    nh, nw = h // factor, w // factor
    return arr[: nh * factor, : nw * factor].reshape(nh, factor, nw, factor).mean(axis=(1, 3))


def block_mad(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.mean(np.abs(a - b)))


# ── Phase 1: Coarse Offset Discovery ──────────────────────────────────────

def phase1_coarse_offsets(gray: np.ndarray, verbose: bool = False) -> list[tuple[int, int, float]]:
    t0 = time.time()
    cropped = center_crop(gray)
    small = downsample(cropped, DOWNSAMPLE_FACTOR)
    h_small = small.shape[0]

    if verbose:
        print(f"  Image {gray.shape[1]}x{gray.shape[0]} → ds {small.shape[1]}x{small.shape[0]}")

    min_d = max(100 // DOWNSAMPLE_FACTOR, COARSE_BLOCK_H + 1)
    max_d = h_small // 2
    results = []

    for d in range(min_d, max_d, COARSE_OFFSET_STEP):
        matches = []
        for y in range(0, h_small - d - COARSE_BLOCK_H, COARSE_SLIDE_STEP):
            ba = small[y : y + COARSE_BLOCK_H]
            bb = small[y + d : y + d + COARSE_BLOCK_H]
            mad = block_mad(ba, bb)
            if mad < COARSE_MAD_THRESH and np.std(ba) > COARSE_MIN_STD:
                matches.append(mad)
        if len(matches) >= MIN_COARSE_MATCHES:
            results.append((d * DOWNSAMPLE_FACTOR, len(matches), float(np.mean(matches))))

    results.sort(key=lambda x: (-x[1], x[2]))

    if verbose:
        print(f"  {len(results)} candidates in {time.time() - t0:.1f}s")
        for off, cnt, mad in results[:10]:
            print(f"    offset={off:5d}px  matches={cnt:3d}  mean_MAD={mad:.2f}")

    return results[:TOP_K_OFFSETS]


# ── Phase 2: Content-Aware Block Matching ─────────────────────────────────

def phase2_content_match(
    gray: np.ndarray,
    candidates: list[tuple[int, int, float]],
    verbose: bool = False,
) -> list[dict]:
    """
    For each offset, slide 100px blocks and classify each as matching
    based on content-row analysis. A block matches if a high fraction
    of its content-rich rows (std > 20) have low per-row MAD (< 8.0).
    """
    t0 = time.time()
    h, w = gray.shape
    all_regions = []

    for offset, _, _ in candidates:
        max_y = h - offset - FINE_BLOCK_H
        if max_y <= 0:
            continue

        matching_blocks = []

        for y in range(0, max_y, FINE_BLOCK_STEP):
            b1 = gray[y : y + FINE_BLOCK_H]
            b2 = gray[y + offset : y + offset + FINE_BLOCK_H]

            row_stds = np.std(b1, axis=1)
            row_mads = np.mean(np.abs(b1 - b2), axis=1)

            content_mask = row_stds > CONTENT_ROW_STD
            n_content = int(content_mask.sum())

            if n_content >= MIN_CONTENT_ROWS:
                content_mads = row_mads[content_mask]
                content_low_frac = float(np.mean(content_mads < CONTENT_ROW_MAD))

                if content_low_frac >= CONTENT_MATCH_FRAC:
                    full_mad = block_mad(b1, b2)
                    matching_blocks.append((y, y + FINE_BLOCK_H, full_mad, content_low_frac))
            # Blocks with too few content rows are ignored — they're
            # background/separator and get included via merge gap only

        if not matching_blocks:
            continue

        # Merge adjacent matching blocks
        merged = _merge_blocks(matching_blocks, MERGE_GAP)

        for y_start, y_end, mean_mad, mean_clf in merged:
            if y_end - y_start < MIN_REGION_H:
                continue

            all_regions.append({
                "y1_start": y_start,
                "y1_end": y_end,
                "y2_start": y_start + offset,
                "y2_end": y_end + offset,
                "offset": offset,
                "block_full_mad": mean_mad,
                "block_content_frac": mean_clf,
            })

    elapsed = time.time() - t0
    if verbose:
        print(f"  {len(all_regions)} candidate regions in {elapsed:.1f}s")
        for r in all_regions:
            rh = r["y1_end"] - r["y1_start"]
            print(f"    y={r['y1_start']:5d}..{r['y1_end']:5d} ({rh:4d}px)  "
                  f"offset={r['offset']:5d}  fMAD={r['block_full_mad']:.2f}  "
                  f"cFrac={r['block_content_frac']:.0%}")

    return all_regions


def _merge_blocks(
    blocks: list[tuple[int, int, float, float]], max_gap: int
) -> list[tuple[int, int, float, float]]:
    if not blocks:
        return []
    blocks.sort(key=lambda b: b[0])
    merged = [list(blocks[0])]
    counts = [1]

    for ys, ye, mad, clf in blocks[1:]:
        if ys - merged[-1][1] <= max_gap:
            merged[-1][1] = max(merged[-1][1], ye)
            # Running average
            n = counts[-1]
            merged[-1][2] = (merged[-1][2] * n + mad) / (n + 1)
            merged[-1][3] = (merged[-1][3] * n + clf) / (n + 1)
            counts[-1] += 1
        else:
            merged.append([ys, ye, mad, clf])
            counts.append(1)

    return [(m[0], m[1], m[2], m[3]) for m in merged]


# ── Phase 3: Validation & Filtering ───────────────────────────────────────

def phase3_validate(
    gray: np.ndarray,
    regions: list[dict],
    verbose: bool = False,
) -> list[dict]:
    t0 = time.time()
    h, w = gray.shape
    validated = []

    for region in regions:
        y1s, y1e = region["y1_start"], region["y1_end"]
        y2s, y2e = region["y2_start"], region["y2_end"]

        if y2e > h:
            continue

        b1 = gray[y1s:y1e]
        b2 = gray[y2s:y2e]

        # Full-width MAD
        full_mad = block_mad(b1, b2)
        if full_mad > FULLWIDTH_MAD_CAP:
            if verbose:
                print(f"    Rejected (full MAD={full_mad:.1f}): y={y1s}-{y1e} offset={region['offset']}")
            continue

        # Content-row analysis on full region
        row_stds = np.std(b1, axis=1)
        row_mads = np.mean(np.abs(b1 - b2), axis=1)
        content_mask = row_stds > CONTENT_ROW_STD
        n_content = int(content_mask.sum())

        if n_content > 0:
            content_mads = row_mads[content_mask]
            content_low_frac = float(np.mean(content_mads < CONTENT_ROW_MAD))
            content_mean_mad = float(np.mean(content_mads))
        else:
            content_low_frac = 1.0
            content_mean_mad = 0.0

        if n_content < MIN_REGION_CONTENT_ROWS:
            if verbose:
                print(f"    Rejected (few content rows={n_content}): "
                      f"y={y1s}-{y1e} offset={region['offset']}")
            continue

        if content_low_frac < REGION_CONTENT_FRAC:
            if verbose:
                print(f"    Rejected (content frac={content_low_frac:.0%}): "
                      f"y={y1s}-{y1e} offset={region['offset']}")
            continue

        # Center-crop validation: reject regions where match is driven by
        # static sidebar rather than actual scrolling content
        cx_start = int(w * 0.15)
        cx_end = int(w * 0.85)
        c1 = gray[y1s:y1e, cx_start:cx_end]
        c2 = gray[y2s:y2e, cx_start:cx_end]
        center_row_stds = np.std(c1, axis=1)
        center_row_mads = np.mean(np.abs(c1 - c2), axis=1)
        center_content_mask = center_row_stds > CONTENT_ROW_STD
        n_center_content = int(center_content_mask.sum())
        if n_center_content >= MIN_CONTENT_ROWS:
            center_content_frac = float(np.mean(
                center_row_mads[center_content_mask] < CONTENT_ROW_MAD
            ))
            if center_content_frac < CENTER_MATCH_FRAC:
                if verbose:
                    print(f"    Rejected (center frac={center_content_frac:.0%}): "
                          f"y={y1s}-{y1e} offset={region['offset']}")
                continue
        elif n_content > 3 * max(n_center_content, 1):
            # Full-width has many content rows but center has very few —
            # the match is driven by static sidebar, not scrolling content
            if verbose:
                print(f"    Rejected (sidebar-driven: {n_content} full vs "
                      f"{n_center_content} center): y={y1s}-{y1e} offset={region['offset']}")
            continue

        # Entropy and stats
        block_std = float(np.std(b1))
        entropy = _block_entropy(b1)

        if entropy < MIN_REGION_ENTROPY:
            if verbose:
                print(f"    Rejected (low entropy={entropy:.2f}): y={y1s}-{y1e}")
            continue
        tight_frac = float(np.mean(row_mads < 3.0))

        # Confidence: content-match quality is primary signal
        confidence = (
            0.40 * content_low_frac
            + 0.30 * max(0, 1.0 - full_mad / FULLWIDTH_MAD_CAP)
            + 0.15 * min(1.0, entropy / 6.0)
            + 0.15 * tight_frac
        )

        region.update({
            "full_width_mad": full_mad,
            "content_low_frac": content_low_frac,
            "content_mean_mad": content_mean_mad,
            "n_content_rows": n_content,
            "block_std": block_std,
            "entropy": entropy,
            "tight_match_frac": tight_frac,
            "confidence": confidence,
        })
        validated.append(region)

    # Refine boundaries to row-level precision
    for region in validated:
        _refine_boundaries(gray, region)

    deduped = _deduplicate_regions(validated)

    if verbose:
        print(f"  {len(validated)} validated → {len(deduped)} after dedup in {time.time() - t0:.1f}s")

    return deduped


def _refine_boundaries(gray: np.ndarray, region: dict):
    """Refine region boundaries to row-level precision.

    Expand outward from the coarse boundaries while per-row MAD stays
    below threshold, then contract inward from both ends while rows
    don't match. This gives tight boundaries around the actual
    duplicated content.
    """
    h = gray.shape[0]
    offset = region["offset"]
    y1s, y1e = region["y1_start"], region["y1_end"]
    EXPAND_LIMIT = 100  # max expansion in each direction
    ROW_MAD_THRESH = 10.0  # per-row threshold for boundary expansion

    # Expand top boundary upward
    check_y = y1s - 1
    for _ in range(EXPAND_LIMIT):
        if check_y < 0 or check_y + offset < 0:
            break
        if np.mean(np.abs(gray[check_y] - gray[check_y + offset])) > ROW_MAD_THRESH:
            break
        check_y -= 1
    y1s = check_y + 1

    # Expand bottom boundary downward
    check_y = y1e
    for _ in range(EXPAND_LIMIT):
        if check_y >= h or check_y + offset >= h:
            break
        if np.mean(np.abs(gray[check_y] - gray[check_y + offset])) > ROW_MAD_THRESH:
            break
        check_y += 1
    y1e = check_y

    # Contract: skip leading/trailing rows with high MAD
    # Use a small sliding window (4 rows) to avoid noise
    WIN = 4
    while y1e - y1s > MIN_REGION_H + WIN:
        chunk_a = gray[y1s : y1s + WIN]
        chunk_b = gray[y1s + offset : y1s + offset + WIN]
        if np.mean(np.abs(chunk_a - chunk_b)) < ROW_MAD_THRESH:
            break
        y1s += 1

    while y1e - y1s > MIN_REGION_H + WIN:
        chunk_a = gray[y1e - WIN : y1e]
        chunk_b = gray[y1e - WIN + offset : y1e + offset]
        if np.mean(np.abs(chunk_a - chunk_b)) < ROW_MAD_THRESH:
            break
        y1e -= 1

    region["y1_start"] = y1s
    region["y1_end"] = y1e
    region["y2_start"] = y1s + offset
    region["y2_end"] = y1e + offset


def _block_entropy(block: np.ndarray) -> float:
    hist, _ = np.histogram(block.ravel(), bins=64, range=(0, 256))
    hist = hist[hist > 0]
    p = hist / hist.sum()
    return float(-np.sum(p * np.log2(p)))


def _deduplicate_regions(regions: list[dict]) -> list[dict]:
    """Remove regions that describe the same duplication found via different offsets.

    Same-offset regions: only dedup if their y1 spans overlap (same content
    matched twice shouldn't happen, but guard against it).

    Cross-offset regions: if region A at offset X covers the same y1↔y2
    mapping as region B at offset Y, suppress the lower-confidence one.
    Only check cross-offset when offsets actually differ — consecutive
    same-offset regions are independent duplications.
    """
    if not regions:
        return []
    regions.sort(key=lambda r: -r["confidence"])
    kept = []
    for region in regions:
        dominated = False
        for existing in kept:
            same_offset = abs(region["offset"] - existing["offset"]) < MIN_REGION_H
            if same_offset:
                # Same offset: only suppress if y1 spans directly overlap
                if _overlap_frac(region["y1_start"], region["y1_end"],
                                 existing["y1_start"], existing["y1_end"]) > 0.5:
                    dominated = True
                    break
            else:
                # Different offset: suppress if this region describes the
                # same content pair already covered by a different offset
                if (_overlap_frac(region["y1_start"], region["y1_end"],
                                  existing["y1_start"], existing["y1_end"]) > 0.5
                    and _overlap_frac(region["y2_start"], region["y2_end"],
                                      existing["y2_start"], existing["y2_end"]) > 0.5):
                    dominated = True
                    break
        if not dominated:
            kept.append(region)
    return kept


def _overlap_frac(a_start, a_end, b_start, b_end) -> float:
    ov = max(0, min(a_end, b_end) - max(a_start, b_start))
    return ov / max(1, a_end - a_start)


# ── Annotation ────────────────────────────────────────────────────────────

def _load_font(size: int):
    """Load a readable monospace font, falling back to default."""
    for path in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/System/Library/Fonts/Supplemental/Courier New.ttf",
        "/Library/Fonts/Courier New.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except (IOError, OSError):
            continue
    return ImageFont.load_default()


def _text_size(draw, text, font):
    """Get text width and height, compatible across Pillow versions."""
    try:
        bbox = font.getbbox(text)
        return bbox[2] - bbox[0], bbox[3] - bbox[1]
    except AttributeError:
        return draw.textsize(text, font=font)


def _draw_hatching(draw, y_start, y_end, x_start, x_end, spacing=30, color=(255, 0, 0, 60)):
    """Draw diagonal hatching lines across a rectangular region."""
    h = y_end - y_start
    for x_off in range(x_start - h, x_end + h, spacing):
        x0, y0 = x_off, y_start
        x1, y1 = x_off + h, y_end
        draw.line([(max(x_start, x0), y0), (min(x_end, x1), y1)], fill=color, width=2)


def annotate_image(image_path: str, regions: list[dict], output_path: str):
    """Annotate the image highlighting DELETE regions for manual editing.

    Design: only B (DELETE) regions get visual fills. A regions are
    reference-only (thin outline + small label). This avoids confusing
    double-colored areas when consecutive same-offset duplications cause
    A and B regions of different pairs to overlap.

    - B regions: red tint + diagonal hatching + thick red border + DELETE label
    - A regions: thin colored outline only (no fill) + reference label
    - Solid red cut-lines at B boundaries with y-coordinate markers
    - Sidebar connector bars linking A↔B pairs with numbering
    - Regions numbered by B position (top→bottom) for editing order
    """
    img = Image.open(image_path).convert("RGBA")
    w, h = img.size

    font_lg = _load_font(22)
    font_md = _load_font(16)
    font_sm = _load_font(13)

    # Sort by B position for editing order (work bottom-to-top)
    sorted_regions = sorted(regions, key=lambda r: r["y2_start"])

    pair_colors = [
        (50, 140, 255),  (240, 120, 0),  (0, 190, 80),
        (190, 0, 190),   (210, 170, 0),  (0, 180, 180),
        (255, 80, 150),  (120, 210, 120),
    ]

    BAR_W = 40

    # ── Pass 1: B region overlays (red tint + hatching) ──
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)

    for r in sorted_regions:
        y2s, y2e = r["y2_start"], r["y2_end"]
        ov_draw.rectangle([BAR_W, y2s, w - 1, y2e], fill=(255, 20, 20, 45))
        _draw_hatching(ov_draw, y2s, y2e, BAR_W, w - 1, spacing=32, color=(255, 0, 0, 40))

    img = Image.alpha_composite(img, overlay)
    draw = ImageDraw.Draw(img)

    # ── Pass 2: borders, sidebar, labels, cut-lines ──
    for seq, r in enumerate(sorted_regions):
        c = pair_colors[seq % len(pair_colors)]
        y1s, y1e = r["y1_start"], r["y1_end"]
        y2s, y2e = r["y2_start"], r["y2_end"]
        rh = y2e - y2s
        num = seq + 1

        # B region: thick red border (3px)
        for i in range(3):
            draw.rectangle([BAR_W + i, y2s + i, w - 1 - i, y2e - i],
                           outline=(255, 30, 30, 255))

        # A region: thin colored outline only (no fill)
        draw.rectangle([BAR_W, y1s, w - 1, y1e], outline=(*c, 170), width=2)

        # ── Sidebar connector bar (A top → B bottom) ──
        draw.rectangle([0, y1s, BAR_W - 1, y2e], fill=(*c, 30))
        draw.rectangle([0, y1s, BAR_W - 1, y2e], outline=(*c, 180), width=2)
        # Divider lines between A/B sections
        draw.line([(0, y1e), (BAR_W - 1, y1e)], fill=(*c, 180), width=2)
        draw.line([(0, y2s), (BAR_W - 1, y2s)], fill=(*c, 180), width=2)

        # Pair number badge
        mid_y = (y1s + y2e) // 2
        draw.rectangle([2, mid_y - 13, BAR_W - 3, mid_y + 13], fill=(0, 0, 0, 220))
        tw, th = _text_size(draw, f"#{num}", font_md)
        draw.text((BAR_W // 2 - tw // 2, mid_y - th // 2), f"#{num}",
                  fill=(255, 255, 255), font=font_md)

        # "A" and "B" markers in sidebar
        draw.text((BAR_W // 2 - 4, y1s + 4), "A", fill=(*c, 220), font=font_sm)
        draw.text((BAR_W // 2 - 4, y2s + 4), "B", fill=(255, 80, 80, 255), font=font_sm)

        # ── Labels ──
        lx = BAR_W + 10

        # B region: prominent DELETE label
        b_text = f" #{num} DELETE  y={y2s}..{y2e}  ({rh}px) "
        tw, th = _text_size(draw, b_text, font_lg)
        ly = y2s + 8
        draw.rectangle([lx, ly, lx + tw + 6, ly + th + 6], fill=(180, 0, 0, 230))
        draw.text((lx + 3, ly + 3), b_text, fill=(255, 255, 255), font=font_lg)

        # B region: MAD info on second line
        mad_text = f" MAD={r.get('full_width_mad', 0):.1f}  content={r.get('content_low_frac', 0):.0%} "
        tw2, th2 = _text_size(draw, mad_text, font_sm)
        ly2 = ly + th + 10
        draw.rectangle([lx, ly2, lx + tw2 + 4, ly2 + th2 + 4], fill=(0, 0, 0, 180))
        draw.text((lx + 2, ly2 + 2), mad_text, fill=(255, 180, 180), font=font_sm)

        # A region: subtle reference label
        a_text = f" #{num} original  y={y1s}..{y1e} "
        tw, th = _text_size(draw, a_text, font_md)
        ly = y1s + 6
        draw.rectangle([lx, ly, lx + tw + 4, ly + th + 4], fill=(0, 0, 0, 180))
        draw.text((lx + 2, ly + 2), a_text, fill=(*c, 255), font=font_md)

        # ── Cut lines at B boundaries (solid red, prominent) ──
        for y in [y2s, y2e]:
            draw.line([(BAR_W, y), (w - 1, y)], fill=(255, 30, 30, 220), width=2)

        # A boundary lines (subtle dashed)
        for y in [y1s, y1e]:
            _draw_dashed_line(draw, BAR_W, w - 1, y, (*c, 120), dash=14, gap=8)

        # ── Y-coordinate markers on right edge ──
        for y in [y2s, y2e]:
            _draw_y_marker(draw, w, y, font_sm, bg=(180, 0, 0, 220), fg=(255, 255, 255))
        for y in [y1s, y1e]:
            _draw_y_marker(draw, w, y, font_sm, bg=(0, 0, 0, 180), fg=(*c, 255))

    img = img.convert("RGB")
    img.save(output_path, quality=95)
    print(f"Annotated image saved to: {output_path}")


def _draw_y_marker(draw, img_w, y, font, bg=(0, 0, 0, 180), fg=(255, 255, 255, 240)):
    """Draw a y-coordinate label on the right edge."""
    label = f" y={y} "
    tw, th = _text_size(draw, label, font)
    x = img_w - tw - 6
    draw.rectangle([x, y - th // 2 - 2, img_w - 1, y + th // 2 + 2], fill=bg)
    draw.text((x + 2, y - th // 2), label, fill=fg, font=font)


def _draw_dashed_line(draw, x0, x1, y, color, dash=10, gap=6):
    """Draw a horizontal dashed line."""
    x = x0
    while x < x1:
        end = min(x + dash, x1)
        draw.line([(x, y), (end, y)], fill=color, width=1)
        x = end + gap


# ── Main ──────────────────────────────────────────────────────────────────

def detect_duplicates(image_path: str, verbose: bool = False) -> list[dict]:
    t0 = time.time()
    print(f"Loading: {image_path}")
    gray = load_grayscale(image_path)
    print(f"Size: {gray.shape[1]}x{gray.shape[0]}")

    print("\n--- Phase 1: Coarse Offset Discovery ---")
    candidates = phase1_coarse_offsets(gray, verbose=verbose)
    if not candidates:
        print("  No candidate offsets.")
        return []

    print("\n--- Phase 2: Content-Aware Block Matching ---")
    regions = phase2_content_match(gray, candidates, verbose=verbose)
    if not regions:
        print("  No matching regions.")
        return []

    print("\n--- Phase 3: Validation & Filtering ---")
    verified = phase3_validate(gray, regions, verbose=verbose)

    elapsed = time.time() - t0
    _print_results(verified, elapsed)
    return verified


def _print_results(regions: list[dict], elapsed: float):
    print(f"\n{'='*60}")
    print(f"RESULTS: {len(regions)} duplicate region(s) in {elapsed:.1f}s")
    print(f"{'='*60}")

    if not regions:
        print("No verified duplicates. Image appears clean.")
        return

    for i, r in enumerate(regions):
        rh = r["y1_end"] - r["y1_start"]
        print(f"\n  Duplicate #{i+1}:")
        print(f"    Region A: y={r['y1_start']}..{r['y1_end']} ({rh}px)")
        print(f"    Region B: y={r['y2_start']}..{r['y2_end']} ({rh}px)")
        print(f"    Offset:   {r['offset']}px")
        print(f"    Full-width MAD:   {r['full_width_mad']:.2f}")
        print(f"    Content-row match: {r['content_low_frac']:.0%} "
              f"({r['n_content_rows']} content rows, mean MAD={r['content_mean_mad']:.1f})")
        print(f"    Tight match: {r['tight_match_frac']:.0%} rows < 3.0")
        print(f"    Confidence: {r['confidence']:.2f}")

    # Delete plan: sorted by B position, bottom-to-top for editing
    delete_bands = sorted(regions, key=lambda r: -r["y2_start"])
    total_delete = sum(r["y2_end"] - r["y2_start"] for r in delete_bands)
    print(f"\n{'─'*60}")
    print(f"DELETE PLAN (work bottom → top, total {total_delete}px):")
    print(f"{'─'*60}")
    for i, r in enumerate(delete_bands):
        rh = r["y2_end"] - r["y2_start"]
        print(f"  {i+1}. Delete rows {r['y2_start']}..{r['y2_end']}  ({rh}px)")


def save_json(regions: list[dict], image_path: str, output_path: str):
    """Save detection results as JSON for programmatic use."""
    import json

    delete_bands = sorted(regions, key=lambda r: r["y2_start"])
    result = {
        "image": str(image_path),
        "duplicates": len(regions),
        "total_delete_px": sum(r["y2_end"] - r["y2_start"] for r in regions),
        "regions": [
            {
                "original": {"y_start": r["y1_start"], "y_end": r["y1_end"]},
                "duplicate": {"y_start": r["y2_start"], "y_end": r["y2_end"]},
                "offset": r["offset"],
                "height": r["y2_end"] - r["y2_start"],
                "full_width_mad": round(r["full_width_mad"], 2),
                "content_match": round(r["content_low_frac"], 3),
                "confidence": round(r["confidence"], 3),
            }
            for r in delete_bands
        ],
        "delete_plan": [
            {"y_start": r["y2_start"], "y_end": r["y2_end"], "height": r["y2_end"] - r["y2_start"]}
            for r in sorted(regions, key=lambda r: -r["y2_start"])
        ],
    }

    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
    print(f"JSON results saved to: {output_path}")


def save_verify_strips(image_path: str, regions: list[dict], output_dir: str):
    """Save side-by-side comparison strips for visual verification."""
    img = Image.open(image_path)
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    sorted_regions = sorted(regions, key=lambda r: r["y2_start"])
    for i, r in enumerate(sorted_regions):
        y1s, y1e = r["y1_start"], r["y1_end"]
        y2s, y2e = r["y2_start"], r["y2_end"]
        rh = y1e - y1s
        w = img.width

        a_strip = img.crop((0, y1s, w, y1e))
        b_strip = img.crop((0, y2s, w, y2e))

        # Side-by-side: A on top, divider, B on bottom
        gap = 4
        combined = Image.new("RGB", (w, rh * 2 + gap), (80, 80, 80))
        combined.paste(a_strip, (0, 0))
        combined.paste(b_strip, (0, rh + gap))

        fname = out / f"dup_{i+1}_compare_y{y2s}-{y2e}.png"
        combined.save(str(fname))
        print(f"  Verify strip: {fname}")


def main():
    parser = argparse.ArgumentParser(description="Detect duplicate regions in stitched screenshots")
    parser.add_argument("image", help="Path to the stitched screenshot")
    parser.add_argument("--annotate", action="store_true", help="Save annotated image")
    parser.add_argument("--json", action="store_true", help="Save results as JSON")
    parser.add_argument("--verify", action="store_true", help="Save side-by-side comparison strips")
    parser.add_argument("--output", type=str, default=None, help="Output path for annotated image")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if not Path(args.image).exists():
        print(f"Error: file not found: {args.image}", file=sys.stderr)
        sys.exit(1)

    regions = detect_duplicates(args.image, verbose=args.verbose)

    stem = Path(args.image).stem
    parent = Path(args.image).parent

    if args.annotate and regions:
        output = args.output or str(parent / f"{stem}-duplicates.png")
        annotate_image(args.image, regions, output)

    if args.json and regions:
        json_path = str(parent / f"{stem}-duplicates.json")
        save_json(regions, args.image, json_path)

    if args.verify and regions:
        verify_dir = str(parent / f"{stem}-verify")
        save_verify_strips(args.image, regions, verify_dir)

    sys.exit(0 if not regions else 1)


if __name__ == "__main__":
    main()
