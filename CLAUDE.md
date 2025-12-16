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
  - `subcategories`: Array of child categories (cascade delete)
  - `people`: Array of people in this category (cascade delete)

- `Person` (Models/Person.swift): Contact information
  - Fields: name, phoneNumber, email, notes
  - `category`: Optional category assignment (nullable relationship)

**Key relationship behavior:**
- Deleting a category cascades to all subcategories and their people
- Deleting a category nullifies the `category` field on associated people
- People can exist without a category

### View Layer

Navigation flows from root categories down through nested subcategories:

- `ContentView`: Entry point that queries and displays root categories (where `parentCategory == nil`)
- `CategoryListView`: Reusable view for any category level, showing subcategories and people
  - Accepts `categories` array and `parentCategory` to determine context
  - Provides add/delete operations for both categories and people at current level
- `PersonDetailView`: Edit individual person with form fields bound via `@Bindable`
- `PersonListView`: Currently unused, displays all people across categories

### Data Flow

1. App initialization sets up SwiftData model container in NamePocketApp.swift:10
2. ContentView queries root categories using FetchDescriptor with predicate
3. CategoryListView recursively navigates through hierarchy
4. All mutations (add/delete) use `modelContext` from environment
5. PersonDetailView uses `@Bindable` for two-way binding with automatic persistence

## Important Patterns

**Querying root categories:** Use `#Predicate { $0.parentCategory == nil }` to get top-level categories (ContentView.swift:10)

**Sorted display:** Views compute sorted arrays on-the-fly (e.g., CategoryListView.swift:14-20) rather than using sortBy in queries

**Previews:** All views include SwiftUI previews with in-memory model containers for development
