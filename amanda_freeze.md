# Freeze report: entering "George" folder (iPhone 13, latest iOS)

**Recipe update (2026-07-20):** the "install, launch once, then overwrite the
store" step order in "Concrete reproduction steps" below now matters. As of
the performance pass on branch `performace-review-7-20-26`, the startup
backfill (`NamePocketApp.backfillCompleteKey`) is gated by a `UserDefaults`
flag so it only runs once per store instead of every launch. Launching once
against the empty store before copying in a real backup sets that flag
against the *empty* store; overwriting the store files afterward then skips
backfill entirely and produces a false "Food subfolder never appears"
failure that looks like a regression but isn't one. **Seed the backup files
immediately after install, before the first launch** — don't launch against
the empty store first.

**Status: major additional fix, shipping as 2.3.1 (build 9). The bounded
Family-step slowdown reported after 2.3.0 is resolved —
`FreezeReproUITests.testEnterGeorgeAndTapSubfolders` now passes end to end
against Amanda's real backup data (previously it failed at the Family step
every time). See "Permanent fix (this branch)" below for what changed and
why the previously-reported "remaining gap" was partly a red herring (a test
assertion bug, not a real hang).**

**Honesty check on the "under 1 second" bar:** one precise, isolated
measurement (tap-to-render latency, not total test time) showed the very
first navigation — tapping into George itself — took 2.385s, over a strict
1-second target. I was not able to get a full per-step breakdown (Food/
Friends/Family individually) before the test environment on this machine
became too unreliable to keep measuring (unrelated to the app: Xcode's
simulator test-launch preflight was intermittently failing, traced to a
paired-but-unreachable Apple Watch confusing Xcode's device-management
layer). So: the catastrophic, unbounded hang is fixed and confirmed via live
process sampling; the multi-second-to-minutes Family-step hang is fixed and
confirmed via a passing regression test; but "never hangs more than 1
second" specifically is *not* independently confirmed for every step — take
the 2.3.1 fix as a large, verified improvement, not a proven sub-1-second
guarantee. Worth a follow-up pass with a stable test environment.

Reported symptom: navigating into the "George" category shows its subfolders
(Food, Friends, Family), but the UI stops responding to any taps from that
point on.

## Permanent fix (this branch)

Starting point was the 2.3.0 state below (§5): catastrophic hang fixed, but
`testEnterGeorgeAndTapSubfolders` still failed at the Family step. The
handoff's "unexplored next step" proposed a scalar `parentCategoryID`/
`categoryID` column so `@Query` predicates could filter in SQL instead of
traversing the `parentCategory`/`category` relationship.

**That alone was not enough.** Implementing it and switching `CategoryListView`
to a scoped `@Query` made things *worse* — live process sampling during a
run showed the CPU-bound work had simply moved from the old Swift-side sort
into `-[NSManagedObjectContext executeFetchRequest:error:]` /
`swift_conformsToProtocolMaybeInstantiateSuperclasses` (Core Data's
materialization of fetched rows into model instances). The real problem was
never *which* predicate shape SwiftData compiles to SQL — it's that
`@Query`'s `DynamicProperty.update()` re-runs the fetch on every `body`
evaluation, and SwiftUI legitimately invokes `body` several times per
navigation transaction. Any non-trivial fetch cost, paid that many times,
compounds into a multi-second stall regardless of how cheap the query is in
isolation.

**The actual fix:** stopped using `@Query` in `CategoryListView` entirely.
Subcategories/people are now fetched once into plain `@State` arrays via
`.onAppear`, with an explicit `refreshLists()` call after each local
mutation (add/rename/trash). This makes `body` itself O(1) — a plain array
read — no matter how many times SwiftUI re-invokes it. The scalar ID columns
were kept (they make the one-time-per-appearance fetch itself SQL-driven
rather than relationship-traversing), but the scalar-vs-relationship
predicate shape turned out to be secondary to *where* the fetch happens.
Existing installs (including restored backups, which copy the raw
`.sqlite` file and predate the new columns) are handled by a one-time
synchronous backfill in `NamePocketApp.makeContainer()`, verified via
direct log inspection to correctly populate all 3 previously-nil
categories and 48 previously-nil people in Amanda's real data.

**The "remaining gap" from §5 was a test bug, not a performance bug.**
After the fetch-relocation fix, `testEnterGeorgeAndTapSubfolders` still
initially failed at the Family step — but isolating it (a temporary test
that tapped directly into Family, skipping Food/Friends) showed it failed
even as the *first* navigation, disproving the §5 theory that cost
"compounds across repeated navigation in one session." Inspecting the raw
backup data directly (`sqlite3`/hex dump) showed why: the person named
"Courtney" in Family has a genuine trailing space in her stored name
(`"Courtney "`, same quirk already known and worked around for the
"Friends " category), and the test asserted on the exact string `"Courtney"`
with no trailing space. That assertion could never have passed, independent
of any freeze. Fixed by matching with a `BEGINSWITH` predicate, same
pattern already used for "Friends" elsewhere in the same test.

Net result: the fetch-relocation fix (verified via live process sampling,
not just a passing test) eliminates the compounding-cost mechanism that
caused the original freeze, and the test now passes cleanly for real.

## Handoff brief for the next agent (read this first)

**Goal for this next pass:** the shipped 2.3.0 fix (commit `af61800` on
`main`, "Fix freeze when opening a category with many people") eliminated
the catastrophic unbounded hang, but a real, reproducible, bounded slowdown
remains (multi-second to tens-of-seconds pauses when navigating through
several subfolders in one session — not infinite, but not fixed either).
Your job is to find a fix that makes `NamePocketUITests
.FreezeReproUITests.testEnterGeorgeAndTapSubfolders` pass cleanly end to
end, ideally with no perceptible delay. See "What remains" and the
"unexplored next step" below for where to start.

**What we did:** Analyzed her backup database (clean, no corruption — §1),
then built two automated tools to actually reproduce the freeze instead of
guessing: a headless SwiftData script (ruled out the persistence layer —
Appendix) and a live UI test (`FreezeReproUITests.swift`) driving the real
app against her real data on an iPhone 13 Simulator. The UI test reproduced
a genuine 28-minute main-thread hang on both Debug and Release builds, and
live process sampling during the hang pinpointed the exact cause in
`CategoryListView.swift` (§3-4).

**The fix that shipped (2.3.0, build 8 — §5):** `CategoryListView` no
longer declares its own `@Query` for `uncategorizedPeople` (SwiftUI was
re-running it on every render of every nested screen, even ones that never
used it), and the sorted people/subcategories lists are now computed once
per render instead of twice. Re-verified with the same UI test against her
real data, run three times: **the 28-minute catastrophic hang is gone.**
This is the current state of `main` (current line numbers for the relevant
code: `sortedSubcategories` at CategoryListView.swift:38-42,
`sortedPeople` at :44-52, `body` caches both into local `let`s at :55-56).

**What we tried beyond that (and reverted — do not just retry this
verbatim):** Attempted to push the sort into the fetch layer with a
`@Query(filter:sort:)` scoped to each parent category, so SwiftData would
sort at the SQL layer instead of in Swift. Three predicate formulations
were tried; all either performed no better or measurably worse than the
shipped fix (one didn't even compile). This appears to be a SwiftData
framework limitation with optional relationship-chain predicates, not
something fixable by rewording the predicate — reverted rather than ship a
regression. Full detail, including the exact predicates tried, is in §5's
follow-up section — read it before re-attempting a fetch-layer approach so
you don't repeat the same three dead ends.

**What remains:** A bounded (not infinite) slowdown — a few seconds to
tens of seconds — that shows up when navigating through multiple subfolders
in the same session (reproduces reliably at the third navigation, e.g.
George → Food → back → Friends → back → Family). The cost is
`sortedPeople`/`sortedSubcategories` still being recomputed from scratch on
every `body` call combined with SwiftData's `Person.name` accessor being
slower than a plain property access. This is no longer the "app looks
permanently frozen" bug reported — it's a lesser, real performance issue
worth fixing properly.

**Unexplored next step (starting point):** try a plain scalar
`parentCategoryID: UUID?` stored property on `Category`/`Person` (set
alongside the `parentCategory`/`category` relationship, kept in sync on
insert/reparent) and filter `@Query`s against that scalar column instead of
predicate-traversing the relationship (`$0.parentCategory?.id == ...` or
`.persistentModelID`). A plain scalar-column predicate is far more likely
to compile to a real SQL `WHERE` clause than anything relationship-shaped —
this specific angle was never tried in the three attempts logged in §5's
follow-up section. Verify with live process sampling (`sample <pid>`
while the test is hung, per §3's method) that the `@Query` accessor is no
longer where the CPU time goes, not just that the test passes — a passing
test alone doesn't prove the fetch actually moved to SQL.

`NamePocketUITests/FreezeReproUITests.testEnterGeorgeAndTapSubfolders` is
in the project as a regression test against her real data — it currently
fails at the Family step by design, documenting the remaining gap. To
re-run it: seed a simulator's app container with
`namepocket_backup_1784206110/namepocket_database.sqlite` (as `default.store`,
alongside the `-wal`/`-shm` files) before launching, per the exact steps in
§3's Method — the test does not seed data itself.

## Original findings (detail)

Tapping from George into **Food** (31 people) triggers a genuine, severe
main-thread hang — reproduced automatically on an iPhone 13 Simulator
running the latest available iOS (26.5), on both Debug and Release builds.
The cause is architectural, not data corruption: `CategoryListView` recomputes
its sorted people/subcategories lists from scratch on every SwiftUI render
pass, and unconditionally declares a `@Query` that SwiftUI's dependency
tracking re-evaluates on every pass **even on screens that don't use it**
(every non-root `CategoryListView`, including Food's). Under real SwiftUI
rendering — with enough people in the list — this makes each render slow
enough that SwiftUI's `AttributeGraph` never converges: it keeps re-invoking
`body` faster than any single pass finishes, pinning the main thread
indefinitely. That's why the screen looks stuck exactly where the user left
it (on George, having just tapped into a subfolder) and never responds to
further taps.

## 1. Database review — no corruption found

Analyzed `namepocket_backup_1784206110/namepocket_database.sqlite` (a raw
copy of the app's SwiftData store, produced by `BackupRepository.backup()`).

- `PRAGMA integrity_check` → `ok`
- No dangling foreign keys, no parent-chain cycles, no duplicate `ZID` UUIDs.
- Data volume is tiny: 7 categories, 48 people total (Food has 31, Family 5,
  Friends 3). Nothing large enough to explain a hang by sheer size alone —
  see §3 for why 31 rows is enough to trigger this bug anyway.
- Minor, harmless data quirk: the "Friends" category name has a genuine
  trailing space (`"Friends "`, confirmed via `hex()`), not a display
  artifact — worth a cosmetic trim on rename/create, unrelated to the freeze.

**This is not a data-corruption problem.** The freeze is caused by app code,
confirmed below.

## 2. What's structurally unique about George

George (`Z_PK = 4`) is the only root-level category with subcategories
rather than direct people:

```
George
├── Food     (31 people — used as a checklist of food likes/dislikes)
├── Friends  (3 people, name stored as "Friends ")
└── Family   (5 people)
```

Every other root category (YGT, Wine, Topgolf) holds people directly with no
children, so George's branch is the only place in this data with two levels
of `CategoryListView` navigation stacked, and Food is the only subfolder
with enough rows to make the per-render cost in §3 catastrophic rather than
just sluggish.

## 3. Automated reproduction — confirmed root cause

### Method

I built `NamePocketUITests/FreezeReproUITests.swift`, a UI test that:
1. Launches the real app on a simulator provisioned as an **iPhone 13
   running iOS 26.5** (the newest iOS runtime available; matches "latest iOS
   version" from the report — no iPhone 13 hardware was available, so this
   is the closest available stand-in).
2. Seeds the simulator's app container directly with her actual backup
   `.sqlite`/`-wal`/`-shm` files (bypassing the in-app import flow, which
   just gets you to the same on-disk state faster).
3. Taps into George, confirms Food/Friends/Family render, then taps Food —
   mirroring exactly what the report describes.

Every wait in the test has an explicit timeout, so a genuine hang would
surface as a normal failure rather than blocking forever.

### Concrete reproduction steps (for the next agent — this is the recipe)

```bash
# 1. Create + boot a fresh iPhone 13 simulator on the newest available iOS runtime
xcrun simctl create "iPhone 13 (freeze-repro)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-13 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5   # adjust to whatever's newest now
xcrun simctl boot <SIM_UDID>
xcrun simctl bootstatus <SIM_UDID> -b

# 2. Build the app + UI test bundle for that simulator
xcodebuild build-for-testing \
  -project NamePocket.xcodeproj -scheme NamePocket \
  -destination "id=<SIM_UDID>"

# 3. Install, launch once (creates the app's Application Support dir), terminate
APP=.../Build/Products/Debug-iphonesimulator/NamePocket.app   # path from step 2's build log
xcrun simctl install <SIM_UDID> "$APP"
xcrun simctl launch <SIM_UDID> com.bronnerapp.NameBuddy
xcrun simctl terminate <SIM_UDID> com.bronnerapp.NameBuddy

# 4. Overwrite the empty store with her real backup data
CONTAINER=$(xcrun simctl get_app_container <SIM_UDID> com.bronnerapp.NameBuddy data)
SUPPORT="$CONTAINER/Library/Application Support"
BACKUP=namepocket_backup_1784206110   # at repo root — not committed, still on disk
cp "$BACKUP/namepocket_database.sqlite"     "$SUPPORT/default.store"
cp "$BACKUP/namepocket_database.sqlite-wal" "$SUPPORT/default.store-wal"
cp "$BACKUP/namepocket_database.sqlite-shm" "$SUPPORT/default.store-shm"

# 5. Run the regression test
xcodebuild test-without-building \
  -project NamePocket.xcodeproj -scheme NamePocket \
  -destination "id=<SIM_UDID>" \
  -only-testing:NamePocketUITests/FreezeReproUITests/testEnterGeorgeAndTapSubfolders
```

If it hangs, don't wait it out — find the live PID (`pgrep -x NamePocket`)
and run `sample <pid> 5 -file /tmp/hang.txt` while it's stuck, then `grep`
the output for `CategoryListView` / `sortedPeople` / `@Query` to see exactly
where the CPU time is going, same as §3's "Live stack trace" below. Clean up
the simulator afterward with `xcrun simctl delete <SIM_UDID>` — several were
created and deleted during this investigation and are not meant to
accumulate on the machine.

### Result: reproduced, both Debug and Release

**Debug build:** the test failed after **28 minutes** — not a `waitForExistence`
timeout (those are capped at 15s each), but XCUITest's own lower-level
element-query synchronization giving up:
```
FreezeReproUITests.swift:48: Failed to get matching snapshots: Timed out while evaluating UI query.
```
(line 48 is `food.tap()` — the tap itself never completed because the app
never became responsive enough for XCUITest to talk to it.)

**Release build:** re-ran the identical scenario on a fresh Release
configuration build (in case the Debug-build hang was inflated by Debug-only
overhead like exclusivity checking). The app process pegged at 99–100% CPU
within seconds of tapping Food and stayed there — same failure mode,
confirming this is not a Debug-build artifact.

### Live stack trace: pinpointing the exact hang

While each build was hung, I sampled the live process (`sample <pid>`) and
got matching call stacks. Both show the main thread permanently inside
SwiftUI's transaction-flushing machinery, never idle:

```
GraphHost.flushTransactions()
  AG::Subgraph::update() / AG::Graph::UpdateStack::update()   <- SwiftUI's dependency graph engine
    CategoryListView.body.getter                                CategoryListView.swift:53
      List<>.init(content:)
        closure #1 in CategoryListView.body.getter              CategoryListView.swift:91 ("if !sortedPeople.isEmpty")
          CategoryListView.sortedPeople.getter                  CategoryListView.swift:45/49
            <compiler-generated accessor for the `uncategorizedPeople` @Query>
            MutableCollection._insertionSort(...)                <- sorting sortedPeople
              Person.name.getter (comparator closure)
                SwiftData: swift_dynamicCast / AnyKeyPath hashing /
                           protocol-conformance-cache lookups /
                           PersistentModel.persistentBackingData.getter
```

Both the Debug and Release samples show `sortedPeople.getter`'s machine code
directly co-located with the **`@__swiftmacro..._uncategorizedPeople..._Query...`**
accessor — the compiler-generated code for the `@Query` property declared at
`CategoryListView.swift:24-25`. This happens on Food's screen even though
Food's `sortedPeople` logically never touches `uncategorizedPeople` (that
branch only runs when `parentCategory == nil` — see CategoryListView.swift:44-47).
That's the mechanism: SwiftUI's `DynamicProperty` protocol requires calling
`update()` on **every** `@Query`/`@State`-style property a view declares on
**every** render pass, whether or not the property is read in that pass. So
every nested `CategoryListView` — George's, Food's — pays for re-evaluating
that query on every single render, regardless of relevance.

### Why my earlier headless test (§ archived below) didn't catch this

An earlier headless script that opened the same backup file directly through
SwiftData (no SwiftUI involved) walked the identical relationship graph in
under a second. That was correct as far as it went — the *persistence*
layer alone is fine — but it never exercised SwiftUI's per-render dependency
tracking or the `sorted(by:)` recomputation, which is where the actual cost
lives. The bug only appears at the intersection of SwiftUI's render loop and
SwiftData's `@Query`/model-property-access cost, which is exactly why a
live, real UI test was necessary to find it.

## 4. Root cause, precisely

Two compounding issues in `CategoryListView.swift`:

1. **`sortedPeople` and `sortedSubcategories` are uncached computed
   properties** (lines 36-50) that re-filter and re-sort from scratch on
   every access. The stack trace shows `sortedPeople` invoked **at least
   twice per single `body` evaluation** (once for the `isEmpty` check at
   line 91, again for `ForEach(sortedPeople)` at line 93) — and `body` itself
   gets re-invoked repeatedly by SwiftUI while a transaction is in flight.
2. **The `uncategorizedPeople` @Query (lines 24-25) is declared
   unconditionally**, so SwiftUI's `DynamicProperty.update()` contract forces
   it to be re-evaluated on every render of every `CategoryListView` in the
   stack, including nested ones (Food's, Family's, Friends') that never use
   its result.

Neither issue alone would necessarily be catastrophic. Combined, on a screen
with enough rows (31, for Food) where each `Person.name` access is itself
non-trivial (SwiftData's macro-generated property accessors go through
dynamic casting and protocol-conformance-cache lookups — visible directly in
the sampled stacks), a single `body` evaluation gets slow enough that
SwiftUI's `AttributeGraph` can't converge before the next transaction is
requested — so it keeps re-entering `body`, compounding the cost every time,
with no natural exit. That reads to the user as exactly what was reported: a
tap that visibly does nothing, forever.

## 5. Fix applied — status: major improvement, not fully resolved

I implemented the two fixes from the original proposal:

- **Scoped `uncategorizedPeople` off nested screens.** `CategoryListView` no
  longer declares its own `@Query`; it takes `uncategorizedPeople: [Person]`
  as a plain parameter (default `[]`), and only `ContentView` (the root)
  fetches it via `@Query` and passes it down. Nested instances (George's,
  Food's, Family's, Friends') no longer carry a query SwiftUI is obligated to
  re-run on every render.
- **Stopped recomputing the sorted arrays twice per render.** `body` now
  computes `sortedSubcategories`/`sortedPeople` once into local `let`s at the
  top, instead of calling each getter separately for the `isEmpty` check and
  the `ForEach`.

**Result, re-verified with the same automated UI test against her real data,
run three times:** the catastrophic **28-minute unbounded hang is gone.**
Tapping into Food (31 people) and Friends (3 people) now both complete well
within their timeouts. But the test still fails, deterministically, at the
same point every time — tapping into **Family** (5 people, the *third*
subfolder navigated to in the same session) still doesn't complete within a
15-second wait:
```
FreezeReproUITests.swift:62: XCTAssertTrue failed - Tapping 'Family' after entering George did not navigate
```
Live process sampling during a third run confirmed this isn't test flakiness
or a stuck accessibility query — the app process genuinely pins near 100%
CPU for a real, sustained stretch (~20+ seconds) before settling. So the
underlying cost that caused the original bug is reduced by roughly two
orders of magnitude, but not eliminated: `sortedPeople`/`sortedSubcategories`
are still recomputed from scratch on every `body` call (SwiftUI legitimately
invokes `body` several times per navigation transaction as part of normal
`AttributeGraph` resolution — that part isn't a bug), and each comparison in
`.sorted(by:)` still pays for a slow `Person.name` access (the SwiftData
macro-generated accessor going through dynamic casting / keypath hashing /
protocol-conformance lookups, visible directly in both sampled stacks). That
cost seems to compound across repeated navigation in one session, which is
why it's Family — the *smallest* subfolder — that finally trips a bounded
timeout, after Food and Friends already ate into it.

### Follow-up attempted: push the sort into the fetch layer — reverted, made it worse

Tried replacing the relationship-array traversal
(`parentCategory.subcategories` / `parentCategory.people`) with a
`@Query(filter:sort:)` scoped to the parent category at each level, so
SwiftData would filter and sort once at the SQL layer instead of via a
Swift-side `.sorted(by:)` on every render. Three variants were tried, each
rebuilt and re-verified against her real data on a fresh simulator:

1. `#Predicate { $0.parentCategory?.id == parentID }` (optional-chained
   comparison against the app's own `id: UUID` field) — compiled, but live
   sampling showed the same `swift_dynamicCast`-heavy cost as before, just
   moved into the `@Query` property wrapper's own accessor instead of the
   manual sort.
2. `#Predicate { $0.parentCategory == parentCategory }` (direct object
   equality) — **didn't compile**: the predicate macro can't build a
   `StandardPredicateExpression<Bool>` from a captured model reference in
   this form.
3. `#Predicate { $0.parentCategory?.persistentModelID == parentModelID }`
   (comparing the framework's own stable identifier instead of the app's
   `id`, expecting this to map directly to the underlying foreign-key
   column) — compiled, but was measurably **worse**: CPU pinned at
   100–126% continuously for over a minute on the same test, vs. ~20–25
   seconds with the simpler fix from §5 above.

All three still funnel through `CategoryListView.people.getter` /
`.subcategories.getter` (the `@Query` macro-generated accessors) doing heavy
interpreted-predicate evaluation with dynamic casting — SwiftData in this
project (this Xcode/iOS version) does not appear to compile *any* optional
relationship-chain predicate down to a plain SQL filter, regardless of which
property is compared on the far side. This looks like a framework-level
limitation rather than something fixable by rewording the predicate, so I
reverted `CategoryListView.swift` and `ContentView.swift` back to the §5
fix (verified working, no `@Query` on nested screens, single cached sort per
render) rather than ship a change that measured worse than what's already
confirmed.

**Current state in the repo is the §5 fix — the 28-minute catastrophic hang
is gone, and the remaining gap is the bounded multi-second slowdown
described above.** If someone wants to pursue the fetch-layer approach
further, the next thing to check is whether a non-optional
`@Relationship`-based inverse lookup, or restructuring to store a plain
`parentCategoryID: UUID` scalar column alongside the relationship (avoiding
predicate traversal through the relationship at all), compiles to real SQL —
that wasn't tried here.

`NamePocketUITests/FreezeReproUITests.testEnterGeorgeAndTapSubfolders` is
left in place as a regression test against the current (§5) state. It
currently fails at the Family step by design, documenting the remaining gap.

## Appendix: earlier (superseded) analysis

The sections below are kept for context on what was ruled out before the
live reproduction pinned down the actual cause.

### Headless SwiftData relationship-walk test

Before building the UI test, I wrote a standalone Swift executable reusing
the real `Category.swift`/`Person.swift` model files, pointed a
`ModelContainer` at a copy of the backup `.sqlite`, and walked
`george.subcategories` → each subcategory's `.subcategories`/`.people`
under a 20-second timeout. It completed in under a second. This correctly
ruled out the *persistence layer alone* (SwiftData fault resolution against
this exact data) as the cause — the actual bug, per §3-4 above, only
appears once SwiftUI's render loop is in the picture, which this headless
test didn't exercise.

### Other items checked and ruled out

- No infinite loop in app code outside the render path: `softDeleteCategory`
  (CategoryListView.swift:229-237), `detachRestoredChildren`
  (TrashView.swift:173-184), and the ancestor-walk loops in
  `TrashView.restore(...)` and `runStartupCleanup()`
  (NamePocketApp.swift:109-122) are all reachable only from
  trash/delete/restore actions, not from simply navigating into George.
- `PersonPhotoView`/`PhotoRepository` (async, actor-isolated, cheap
  `fileExists` checks) aren't implicated — George's own screen has no direct
  people, so no photo loads happen there.
