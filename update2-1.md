# NamePocket 2.1 — Feature Planning

Three features under consideration. For each, options are listed with pros/cons and a recommendation.

---

## Feature 1: Swipe-to-Delete Confirmation

Currently `onDelete` in `CategoryListView` immediately calls `modelContext.delete()` with no confirmation. We want a confirmation step before the deletion completes.

### Option A — Intercept `onDelete` with a `confirmationDialog`

Store the pending index set in state, show a `.confirmationDialog`, and only delete on confirm.

**Pros:**
- Minimal code change — keeps `onDelete`/Edit-mode behavior
- Familiar iOS pattern

**Cons:**
- SwiftUI plays the swipe animation *before* the dialog appears, so the row visually vanishes before the user confirms. If they cancel, the row snaps back — looks glitchy.
- The `IndexSet` passed to `onDelete` may become stale by the time the dialog dismisses if the list reloads.

### Option B — Replace `onDelete` with explicit `.swipeActions` (Recommended)

Remove `onDelete` and add `.swipeActions(edge: .trailing)` with a red trash button per row. Tapping it sets a `@State` variable (`itemToDelete`) and shows a `confirmationDialog`. The row stays visible until confirmed.

**Pros:**
- No animation jank — the row stays in place until the user decides
- Full control over button label, icon, and color (red trash can looks native)
- Works cleanly with the `confirmationDialog` modifier
- Natural path to Feature 2 (trash) — confirmation can say "Move to Trash" instead of "Delete"

**Cons:**
- Loses Edit-mode multi-delete (the red minus buttons). Most users never use Edit mode for deletion, so this is a low-cost tradeoff. Edit mode can still be kept for reordering if needed later.

### Option C — Alert on `onDelete`

Same as Option A but using `.alert` instead of `.confirmationDialog`.

**Pros:** Very simple

**Cons:** Alerts are semantically for errors/info, not destructive actions. Has the same animation-jank problem as A. Not recommended for destructive confirmations in modern iOS HIG.

### Recommendation: **Option B**

`.swipeActions` gives the cleanest UX and sets up Feature 2 naturally (the button can say "Move to Trash" once the trash is built).

**Files to change:** `CategoryListView.swift` — both the categories `ForEach` and the people `ForEach`.

---

## Feature 2: Trash Can with 30-Day Restore

Deleted items move to a trash rather than being permanently destroyed. Users can restore or permanently delete from the trash. Items auto-purge after 30 days.

### Option A — Soft-Delete Flag on Existing Models (Recommended)

Add `deletedAt: Date?` to both `Person` and `Category`. On "delete," set `deletedAt = Date()` instead of calling `modelContext.delete()`. All live queries gain a predicate excluding soft-deleted items. A Trash view queries items where `deletedAt != nil`. Restore nils out `deletedAt`. Permanent delete calls `modelContext.delete()`. App startup purges items where `deletedAt` is older than 30 days.

**Pros:**
- No new model types — minimal schema change
- SwiftData predicates handle filtering cleanly
- Relationships are preserved on disk (a person still knows its category even while trashed)
- Restore is simple: set `deletedAt = nil`
- For categories: recursively soft-delete subcategories and their people on deletion (preserves the hierarchy for restore)

**Cons:**
- Every existing query needs an updated predicate to exclude soft-deleted items (ContentView and CategoryListView). Not many queries, but easy to miss one.
- Restoring a person whose category was also deleted requires a decision: restore the category too, or move the person to "Uncategorized." (Recommend: if the parent category is still trashed, restore it alongside the person, or offer a choice.)
- Restoring a category with soft-deleted children needs to recursively restore them too.

### Option B — Separate `TrashedItem` Model

A new `TrashedItem` SwiftData model stores serialized snapshots: `originalType` (person/category), a JSON blob of the item's data, `deletedAt: Date`, and enough info to reconstruct it (original category name/id for a person, etc.).

**Pros:**
- Zero impact on existing live-data queries — no predicate changes needed
- Clean separation: trash is entirely its own thing

**Cons:**
- Category hierarchies are hard to serialize — a deleted category with 3 nested subcategories and 20 people requires serializing the whole subtree
- Restore must recreate SwiftData objects from JSON, which means manually reconstructing relationships — fragile and verbose
- Photos (stored as files) need separate handling; the current system keys photos to `person.id.uuidString`, so a restored person gets a new UUID and loses its photo unless the filename is preserved separately
- Significantly more code for a first-pass feature

### Option C — Hidden "Trash" Category

Create a system category with a reserved name (`__trash__`) and move deleted people into it instead of deleting them. Deleted categories become subcategories of it.

**Pros:**
- Zero model changes

**Cons:**
- Deeply hacky — reserved names are fragile, the category shows up in backups/exports, cascade delete behavior becomes unpredictable, and restoring category hierarchies is still complex. Not recommended.

### Recommendation: **Option A**

The predicate updates are a known, bounded cost. The recursive soft-delete/restore logic is straightforward. Photos are naturally preserved because the person's UUID (and thus filename) never changes during trash/restore.

**Implementation sketch:**
- Add `deletedAt: Date?` to `Person.swift` and `Category.swift`
- Update `ContentView` and `CategoryListView` queries to exclude soft-deleted items
- New `TrashView.swift` — lists all soft-deleted people and categories, grouped, with age shown
- Trash accessible from a toolbar button on `ContentView` (trash can icon, badged with count)
- Startup cleanup in `NamePocketApp.runStartupCleanup()` — fetch all items where `deletedAt` < 30 days ago and permanently delete them, then prune photo orphans

---

## Feature 3: Notes Preview Below Person Name

Show the first line of a person's notes as a subtitle in the list row. Toggleable, on by default.

### Option A — Settings Toggle Only

Add a `@AppStorage("showNotesPreview") var showNotesPreview = true` and a toggle row in `SettingsView`. In `CategoryListView`, show a subtitle `Text` when the setting is on and notes are non-empty.

**Pros:**
- Dead simple — one bool, one UI change
- Settings is a natural home for display preferences

**Cons:**
- Buried in Settings — users who want to quickly toggle it have to navigate away from the list. Discoverability is low, especially since it's on by default and users might not know it can be turned off.

### Option B — Toolbar Toggle Button (Recommended)

Add an eye (or lines) icon button to the `CategoryListView` toolbar that toggles the preview. Persist state with `@AppStorage` so it survives app restarts. The icon changes state to indicate current mode (e.g., `eye` vs `eye.slash`).

**Pros:**
- Immediately visible and accessible — no Settings navigation required
- Persists via `@AppStorage` (one line of code)
- Consistent with standard iOS list-density controls (e.g., Mail, Reminders)
- The icon is self-explanatory; no need to label it

**Cons:**
- Adds another toolbar button. The toolbar currently has a "+" menu button (trailing) and a settings gear (leading). Adding a toggle (e.g., trailing alongside "+") is fine on standard screen sizes.

### Option C — Per-Row Long-Press Toggle

Each person row can individually show or hide its notes snippet, toggled by long-press.

**Pros:** Maximum granularity

**Cons:** Not what was described, hard to discover, and state would be awkward to persist per-person without model changes or a large `@AppStorage` dictionary. Overkill.

### Recommendation: **Option B**

A toolbar toggle with `@AppStorage` gives users quick access to the control while keeping it persistent. One `@AppStorage` key, one toolbar button, one conditional `Text` view in the row label.

**Implementation sketch:**
- `@AppStorage("showNotesPreview") private var showNotesPreview = true` in `CategoryListView`
- Trailing toolbar button: `Image(systemName: showNotesPreview ? "text.below.photo" : "text.below.photo")` — or simpler: `eye` / `eye.slash`
- In the People `ForEach` row label, replace `Text(person.name)` with a `VStack(alignment: .leading)` containing the name and (conditionally) a `.caption` / `.foregroundStyle(.secondary)` text of `person.notes.components(separatedBy: "\n").first`
- Show the subtitle only when `showNotesPreview && !person.notes.isEmpty`
- Notes with no newlines show the full (short) note; long first lines truncate with `.lineLimit(1)`

---

## Suggested Implementation Order

1. **Feature 3** (Notes Preview) — isolated, no model changes, lowest risk. Good warm-up.
2. **Feature 1** (Swipe confirmation) — small, self-contained change to `CategoryListView`. Naturally transitions to Feature 2 by changing button label to "Move to Trash."
3. **Feature 2** (Trash) — largest change. Requires model migration (new fields), query updates, new view, and startup cleanup.
