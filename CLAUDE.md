# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NamePocket is an iOS contact management app built with SwiftUI and SwiftData. It organizes contacts into hierarchical categories with unlimited nesting depth.

## Build and Run

This is an Xcode project. To build and run:

```bash
# Open in Xcode
open NamePocket.xcodeproj

# Build from command line
xcodebuild -project NamePocket.xcodeproj -scheme NamePocket build

# Run tests (if tests exist)
xcodebuild -project NamePocket.xcodeproj -scheme NamePocket test
```

## Architecture

### Data Layer (SwiftData)

The app uses SwiftData for persistence with two core models:

- `Category` (Models/Category.swift): Hierarchical categories with self-referencing relationships
  - `parentCategory`: Optional parent (nullable relationship)
  - `parentCategoryID`: Scalar `UUID?` mirror of `parentCategory?.id`, kept in sync manually at every write site
  - `subcategories`: Array of child categories (cascade delete)
  - `people`: Array of people in this category (cascade delete)

- `Person` (Models/Person.swift): Contact information
  - Fields: name, phoneNumber, email, notes
  - `category`: Optional category assignment (nullable relationship)
  - `categoryID`: Scalar `UUID?` mirror of `category?.id`, kept in sync manually at every write site

**Why the scalar ID mirrors exist:** SwiftData in this project does not compile
predicates that traverse a relationship (e.g. `parentCategory?.id == ...`) down
to SQL — it evaluates them in Swift instead, which caused a severe freeze (see
`amanda_freeze.md`). Filtering on the scalar `parentCategoryID`/`categoryID`
columns instead lets fetches happen in SQL. Existing stores (including
restored backups) predate these columns and are backfilled once via
`NamePocketApp.backfillScalarParentIDsIfNeeded`, gated by a `UserDefaults`
flag so the backfill's full-table fetch only runs once per store rather than
every launch.

**Key relationship behavior:**
- Deleting a category cascades to all subcategories and their people
- Deleting a category nullifies the `category` field on associated people
- People can exist without a category

### View Layer

Navigation flows from root categories down through nested subcategories:

- `ContentView`: Entry point; hosts the `NavigationStack` and delegates the root category list to `CategoryListView(parentCategory: nil)`. Uses `@Query` itself only for the trash-count toolbar badge (a cheap count at the root, not a hot render path)
- `CategoryListView`: Reusable view for any category level, showing subcategories and people
  - Takes a `parentCategory: Category?` and fetches its subcategories/people on demand into plain `@State` arrays (`refreshLists()`), **not** via `@Query` — see below
  - At the root level (no parent category) it also lists uncategorized people
  - Provides add/delete operations for both categories and people at current level
- `TrashView`: Same `@State` + on-demand-fetch pattern as `CategoryListView` (`refreshTrash()`), for the same reason
- `PersonDetailView`: Edit individual person with form fields bound via `@Bindable`

### Data Flow

1. App initialization sets up SwiftData model container in NamePocketApp.swift, backfilling the scalar ID columns once per store
2. `CategoryListView`/`TrashView` fetch their contents on `.onAppear` into `@State` arrays via `FetchDescriptor` predicates on the scalar ID columns, and re-fetch explicitly after each local mutation
3. `CategoryListView` recursively navigates through the hierarchy via `NavigationLink`
4. All mutations (add/delete/restore) use `modelContext` from environment, followed by an explicit refresh of the local `@State`
5. `PersonDetailView` uses `@Bindable` for two-way binding with automatic persistence

## Important Patterns

**Do not use `@Query` for `CategoryListView`/`TrashView`'s main content.** SwiftUI's `DynamicProperty` contract re-runs a `@Query`'s fetch on every `body` evaluation, and `body` is legitimately invoked several times per navigation transaction — for a list with many rows this compounded into a multi-second-to-minutes freeze (see `amanda_freeze.md`). Both views instead fetch once into `@State` on `.onAppear`/after mutations. This is a deliberate, verified-by-regression-test exception to "use `@Query`" as a general default elsewhere — don't revert it without re-reading `amanda_freeze.md` and rerunning `NamePocketUITests/FreezeReproUITests`.

**Sorted display:** Views compute sorted arrays once during the fetch (e.g. `CategoryListView.refreshLists()`, `TrashView.refreshTrash()`) rather than as a computed property re-evaluated on every render.

**Previews:** All views include SwiftUI previews with in-memory model containers for development

## App Store Preparation

A custom skill is available for App Store submission automation using fastlane.

### Using the App Store Prep Skill

```bash
/skill app-store-prep
```

The skill automates:
- Screenshot generation across all required device sizes
- App Store metadata management
- Building and uploading to TestFlight/App Store

### Fastlane Commands

```bash
# Install dependencies
bundle install

# Generate screenshots (requires UI test target)
bundle exec fastlane screenshots

# Update metadata on App Store Connect
bundle exec fastlane metadata

# Build IPA
bundle exec fastlane build

# Upload to TestFlight
bundle exec fastlane beta

# Upload to App Store
bundle exec fastlane release

# Complete preparation (screenshots + metadata)
bundle exec fastlane prepare_appstore
```

### First-Time Setup Required

1. Configure `fastlane/Appfile` with your Apple Developer credentials and bundle ID
2. Create UI test target (see `.claude/skills/app-store-prep/ui-test-setup.md`)
3. Customize metadata files in `fastlane/metadata/en-US/`
4. Set up App Store Connect API key or app-specific password

See `.claude/skills/app-store-prep/README.md` for complete documentation.
