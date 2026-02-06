# Design System Guide

**Purpose:** Fluid design tokens for consistent, responsive scaling across all templates.

**Status:** Active reference document

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Token Values](#token-values)
3. [Usage Patterns](#usage-patterns)
4. [Find/Replace Patterns](#findreplace-patterns)
5. [Common Mistakes](#common-mistakes)
6. [Examples](#examples)

---

## Quick Reference

### Spacing Tokens

| Hardcoded | Design Token | Fluid Range | Usage |
|-----------|--------------|-------------|-------|
| `gap-1`, `m-1`, `p-1` | `[var(--space-inline)]` | 4px → 8px | Tiny gaps, inline spacing |
| `gap-2`, `mt-2`, `px-2` | `[var(--space-xs)]` | 4px → 8px | Extra small spacing |
| `gap-3`, `p-3` | `[var(--space-xs)]` | 4px → 8px | Use xs (no 3 token) |
| `gap-4`, `mb-4`, `p-4` | `[var(--space-sm)]` | 8px → 16px | Small spacing, card padding |
| `gap-6`, `pb-6`, `mt-6` | `[var(--space-md)]` | 16px → 32px | Medium spacing, sections |
| `gap-8`, `mt-8`, `mb-8` | `[var(--space-lg)]` | 32px → 64px | Large spacing, major sections |
| `gap-12`, `mt-12` | `[var(--space-xl)]` | 48px → 96px | Extra large, page sections |

### Typography Tokens

| Hardcoded | Design Token | Fluid Range | Usage |
|-----------|--------------|-------------|-------|
| `text-xs` | `[var(--text-xs)]` | 12px → 14px | Fine print, captions |
| `text-sm` | `[var(--text-sm)]` | 14px → 16px | Body text, labels |
| `text-base` | `[var(--text-base)]` | 16px → 20px | Primary body text |
| `text-lg` | `[var(--text-lg)]` | 18px → 24px | Subheadings (h3) |
| `text-xl` | `[var(--text-xl)]` | 20px → 32px | Section headings (h2) |
| `text-2xl` | `[var(--text-2xl)]` | 24px → 48px | Page titles (h1) |

### Layout Tokens

| Hardcoded | Design Token | Value | Usage |
|-----------|--------------|-------|-------|
| `max-w-7xl` | `max-w-[var(--content-max-width)]` | min(95vw, 1400px) | Main containers |
| `max-w-4xl` | `max-w-[var(--article-max-width)]` | min(90vw, 800px) | Article width |
| `max-w-xl` | `max-w-[var(--card-max-width)]` | min(90vw, 600px) | Card max width |
| `w-64` | `w-[var(--sidebar-width)]` | max(250px, 20vw) | Sidebar width |

---

## Token Values

These are defined in `assets/css/app.css`:

```css
/* Spacing (spacing.css) */
--space-inline: clamp(0.25rem, 0.5vw, 0.5rem);
--space-xs: clamp(0.25rem, 1vw, 0.5rem);
--space-sm: clamp(0.5rem, 2vw, 1rem);
--space-md: clamp(1rem, 3vw, 2rem);
--space-lg: clamp(2rem, 5vw, 4rem);
--space-xl: clamp(3rem, 8vw, 6rem);

/* Typography (typography.css) */
--text-xs: clamp(0.75rem, 1vw, 0.875rem);
--text-sm: clamp(0.875rem, 1.5vw, 1rem);
--text-base: clamp(1rem, 2vw, 1.25rem);
--text-lg: clamp(1.125rem, 2.5vw, 1.5rem);
--text-xl: clamp(1.25rem, 3vw, 2rem);
--text-2xl: clamp(1.5rem, 4vw, 3rem);

/* Layout */
--content-max-width: min(95vw, 1400px);
--article-max-width: min(90vw, 800px);
--card-max-width: min(90vw, 600px);
--sidebar-width: max(250px, 20vw);
```

---

## Usage Patterns

### Basic Template Pattern

```heex
<div class="space-y-[var(--space-md)]">
  <h1 class="text-[var(--text-2xl)] font-bold">Page Title</h1>
  <p class="text-[var(--text-base)]">Body content here.</p>

  <div class="flex gap-[var(--space-xs)]">
    <button class="btn btn-primary">Action</button>
  </div>
</div>
```

### Card Pattern

```heex
<div class="card bg-base-200 shadow-lg">
  <div class="card-body">
    <div class="flex items-start justify-between gap-[var(--space-sm)]">
      <h3 class="card-title text-[var(--text-xl)]">Card Title</h3>
      <div class="flex gap-[var(--space-inline)]">
        <button class="btn btn-sm btn-ghost">Edit</button>
      </div>
    </div>
    <p class="text-[var(--text-sm)]">Card description text.</p>
  </div>
</div>
```

### Form Pattern

```heex
<div class="space-y-[var(--space-sm)]">
  <div class="form-control">
    <label class="label">
      <span class="label-text text-[var(--text-sm)]">Email</span>
    </label>
    <input type="email" class="input input-bordered" />
  </div>

  <div class="flex gap-[var(--space-xs)] mt-[var(--space-md)]">
    <button class="btn btn-primary">Submit</button>
    <button class="btn btn-ghost">Cancel</button>
  </div>
</div>
```

### Grid Layout Pattern

```heex
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-[var(--space-md)]">
  <div class="card">
    <div class="card-body p-[var(--space-sm)]">
      <h3 class="text-[var(--text-lg)] font-semibold mb-[var(--space-xs)]">Title</h3>
      <p class="text-[var(--text-sm)]">Description</p>
    </div>
  </div>
</div>
```

### Page Container Pattern

```heex
<div class="w-[var(--content-max-width)] mx-auto">
  <article class="w-[var(--article-max-width)] mx-auto">
    <h1 class="text-[var(--text-2xl)]">Article Title</h1>
    <div class="prose text-[var(--text-base)]">
      Content here...
    </div>
  </article>
</div>
```

---

## Find/Replace Patterns

Use your editor's find/replace with regex:

### Spacing

```
Find: \bgap-1\b          → Replace: gap-[var(--space-inline)]
Find: \bgap-2\b          → Replace: gap-[var(--space-xs)]
Find: \bgap-3\b          → Replace: gap-[var(--space-xs)]
Find: \bgap-4\b          → Replace: gap-[var(--space-sm)]
Find: \bgap-6\b          → Replace: gap-[var(--space-md)]
Find: \bgap-8\b          → Replace: gap-[var(--space-lg)]

Find: \bm(t|b|l|r)-2\b   → Replace: m$1-[var(--space-xs)]
Find: \bm(t|b|l|r)-4\b   → Replace: m$1-[var(--space-sm)]
Find: \bm(t|b|l|r)-6\b   → Replace: m$1-[var(--space-md)]
Find: \bm(t|b|l|r)-8\b   → Replace: m$1-[var(--space-lg)]

Find: \bp(x|y|t|b|l|r)-2\b → Replace: p$1-[var(--space-xs)]
Find: \bp(x|y|t|b|l|r)-4\b → Replace: p$1-[var(--space-sm)]
Find: \bp(x|y|t|b|l|r)-6\b → Replace: p$1-[var(--space-md)]

Find: \bspace-y-4\b      → Replace: space-y-[var(--space-sm)]
Find: \bspace-y-6\b      → Replace: space-y-[var(--space-md)]
```

### Typography

```
Find: \btext-xs\b        → Replace: text-[var(--text-xs)]
Find: \btext-sm\b        → Replace: text-[var(--text-sm)]
Find: \btext-base\b      → Replace: text-[var(--text-base)]
Find: \btext-lg\b        → Replace: text-[var(--text-lg)]
Find: \btext-xl\b        → Replace: text-[var(--text-xl)]
Find: \btext-2xl\b       → Replace: text-[var(--text-2xl)]
```

---

## Common Mistakes

### 1. Don't Migrate DaisyUI Classes

**❌ Wrong:**
```heex
<button class="btn btn-[var(--space-sm)]">
```

**✅ Correct:**
```heex
<button class="btn btn-primary gap-[var(--space-xs)]">
```

DaisyUI component classes (`btn`, `card`, `badge`, `input`) are semantic - don't tokenize them.

### 2. Don't Migrate Icon Sizes

**❌ Wrong:**
```heex
<.icon name="hero-tag" class="h-[var(--space-sm)] w-[var(--space-sm)]" />
```

**✅ Correct:**
```heex
<.icon name="hero-tag" class="h-5 w-5" />
```

Fixed-size utilities (`h-5`, `w-5`, `size-6`) are intentional and shouldn't be fluid.

### 3. Keep Color Utilities As-Is

**✅ No migration needed:**
```heex
<div class="text-gray-600 bg-base-200 border-primary">
```

Color utilities don't need migration.

### 4. Container Queries Handle Cards Automatically

If using `.post-card` or `.listing-card` classes, container queries in `app.css` already apply fluid tokens. Don't duplicate.

### 5. Mixed Token Usage is OK

**✅ Correct:**
```heex
<div class="flex items-center gap-[var(--space-xs)] text-[var(--text-sm)] text-gray-600">
```

Mix design tokens (spacing, typography) with standard utilities (flex, colors).

---

## Examples

### Before/After: Stepped Form Header

**Before:**
```heex
<h2 class="text-2xl font-semibold">{gettext("Step 1: Project Basics")}</h2>
<p class="text-base-content/70">Description text</p>
```

**After:**
```heex
<h2 class="text-[var(--text-2xl)] font-semibold">{gettext("Step 1: Project Basics")}</h2>
<p class="text-base-content/70">Description text</p>
```

### Before/After: Grid with Cards

**Before:**
```heex
<div class="grid grid-cols-2 gap-3 md:grid-cols-4">
  <label class="card p-4">
    <span class="text-sm font-medium">{template.name}</span>
  </label>
</div>
<p class="text-base-content/60 mt-2 text-sm">Help text</p>
```

**After:**
```heex
<div class="grid grid-cols-2 gap-[var(--space-xs)] md:grid-cols-4">
  <label class="card p-[var(--space-sm)]">
    <span class="text-[var(--text-sm)] font-medium">{template.name}</span>
  </label>
</div>
<p class="text-base-content/60 mt-[var(--space-xs)] text-[var(--text-sm)]">Help text</p>
```

### Before/After: Section with Items

**Before:**
```heex
<h3 class="mb-4 text-lg font-semibold">{gettext("Collaborators")}</h3>
<div class="grid grid-cols-1 gap-3 md:grid-cols-2">
  <div class="flex items-center gap-2">
    <span class="text-sm">{collab.name}</span>
  </div>
</div>
```

**After:**
```heex
<h3 class="mb-[var(--space-sm)] text-[var(--text-lg)] font-semibold">{gettext("Collaborators")}</h3>
<div class="grid grid-cols-1 gap-[var(--space-xs)] md:grid-cols-2">
  <div class="flex items-center gap-[var(--space-xs)]">
    <span class="text-[var(--text-sm)]">{collab.name}</span>
  </div>
</div>
```

---

## What NOT to Migrate

Keep these as hardcoded values:

- **Icon sizes:** `h-5 w-5`, `h-6 w-6`, `size-4`
- **DaisyUI classes:** `btn`, `btn-sm`, `btn-lg`, `card`, `badge`
- **Color utilities:** `text-gray-600`, `bg-base-200`, `border-primary`
- **Structural utilities:** `flex`, `grid`, `items-center`, `justify-between`
- **Grid columns:** `grid-cols-2`, `md:grid-cols-4`
- **Specific widths for images:** `w-40`, `h-24` (intentional fixed sizes)

---

## Testing After Migration

```bash
# Run all tests
mix test.all

# Visual testing checklist:
# - Mobile (375px)
# - Tablet (768px)
# - Desktop (1440px)
```

---

## Token Reference Files

- `assets/css/app.css` - All design tokens (spacing, typography, layout) and container queries

---

**Last Updated:** 2025-12-10
