---
name: arc-helper-library
kind: driver
version: 0.2.0
description: Pre-built utility functions for common ARC grid operations
author: sl
tags: [arc, utilities, pattern-recognition]
requires: []
---

## ARC Helper Library

These utility functions handle common ARC operations that are surprisingly hard to implement correctly under iteration pressure. Copy only the functions you need — do not copy the entire library if you only need grid basics.

### Grid Basics

```python
def grid_dims(grid): return (len(grid), len(grid[0]))
def grid_equal(a, b): return a == b
def grid_copy(grid): return [row[:] for row in grid]
def grid_new(H, W, fill=0): return [[fill]*W for _ in range(H)]
def subgrid(grid, r1, c1, r2, c2):
    return [row[c1:c2] for row in grid[r1:r2]]
```

### Color Analysis

```python
from collections import Counter

def color_counts(grid):
    counts = Counter()
    for row in grid:
        for c in row:
            counts[c] += 1
    return dict(counts)

def colors_present(grid):
    return sorted(set(c for row in grid for c in row))

def background_color(grid):
    counts = color_counts(grid)
    return max(counts, key=counts.get)

def classify_colors(grid):
    counts = color_counts(grid)
    sorted_colors = sorted(counts, key=counts.get, reverse=True)
    bg = sorted_colors[0]
    fg = sorted_colors[1:]
    return {"background": bg, "foreground": fg}
```

### Dividers and Regions

```python
def find_row_dividers(grid):
    bg = background_color(grid)
    dividers = []
    for r, row in enumerate(grid):
        vals = set(row)
        if len(vals) == 1 and bg not in vals:
            dividers.append(r)
    return dividers

def find_col_dividers(grid):
    bg = background_color(grid)
    H, W = grid_dims(grid)
    dividers = []
    for c in range(W):
        vals = set(grid[r][c] for r in range(H))
        if len(vals) == 1 and bg not in vals:
            dividers.append(c)
    return dividers

def split_by_dividers(grid, row_divs, col_divs):
    r_bounds = [-1] + row_divs + [len(grid)]
    c_bounds = [-1] + col_divs + [len(grid[0])]
    regions = []
    for ri in range(len(r_bounds) - 1):
        region_row = []
        for ci in range(len(c_bounds) - 1):
            region_row.append(subgrid(grid,
                r_bounds[ri] + 1, c_bounds[ci] + 1,
                r_bounds[ri + 1], c_bounds[ci + 1]))
        regions.append(region_row)
    return regions
```

### Symmetry Testing

```python
def reflect_h(grid): return [row[::-1] for row in grid]
def reflect_v(grid): return grid[::-1]
def rotate90(grid):
    H, W = grid_dims(grid)
    return [[grid[H - 1 - r][c] for r in range(H)] for c in range(W)]
def rotate180(grid): return reflect_v(reflect_h(grid))
def rotate270(grid): return rotate90(rotate90(rotate90(grid)))
def transpose(grid):
    H, W = grid_dims(grid)
    return [[grid[r][c] for r in range(H)] for c in range(W)]

def test_all_symmetries(grid, target):
    ops = [
        ("identity",  grid),
        ("reflectH",  reflect_h(grid)),
        ("reflectV",  reflect_v(grid)),
        ("rotate90",  rotate90(grid)),
        ("rotate180", rotate180(grid)),
        ("rotate270", rotate270(grid)),
        ("transpose", transpose(grid)),
    ]
    for name, result in ops:
        if grid_equal(result, target):
            return name
    return None
```

### Connected Components

```python
def label_components(grid, ignore_color=0):
    H, W = grid_dims(grid)
    labels = grid_new(H, W, 0)
    comp_id = 0
    for r in range(H):
        for c in range(W):
            if labels[r][c] == 0 and grid[r][c] != ignore_color:
                comp_id += 1
                stack = [(r, c)]
                color = grid[r][c]
                while stack:
                    cr, cc = stack.pop()
                    if cr < 0 or cr >= H or cc < 0 or cc >= W:
                        continue
                    if labels[cr][cc] != 0 or grid[cr][cc] != color:
                        continue
                    labels[cr][cc] = comp_id
                    stack.extend([(cr-1,cc),(cr+1,cc),(cr,cc-1),(cr,cc+1)])
    return {"labels": labels, "count": comp_id}

def bounding_box(grid, predicate):
    min_r, max_r = float('inf'), -1
    min_c, max_c = float('inf'), -1
    for r, row in enumerate(grid):
        for c, val in enumerate(row):
            if predicate(val, r, c):
                min_r = min(min_r, r); max_r = max(max_r, r)
                min_c = min(min_c, c); max_c = max(max_c, c)
    if max_r == -1:
        return None
    return {"min_r": min_r, "max_r": max_r, "min_c": min_c, "max_c": max_c,
            "height": max_r - min_r + 1, "width": max_c - min_c + 1}
```

### Concentric Rectangle Fill

```python
def fill_concentric_rects(H, W, colors):
    grid = grid_new(H, W)
    layers = (min(H, W) + 1) // 2
    for layer in range(layers):
        color = colors[layer % len(colors)]
        for r in range(layer, H - layer):
            for c in range(layer, W - layer):
                grid[r][c] = color
    return grid
```

### Usage

Copy only the functions relevant to your task. They are tested and correct — you do not need to re-derive them. Spend your iteration budget on understanding the transformation rule, not reimplementing grid utilities. If a helper does not fit your task's needs, write your own — these are reference implementations, not mandates.
