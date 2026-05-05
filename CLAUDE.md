# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run full test suite
bundle exec rake        # or: bundle exec rspec

# Run a single spec file
bundle exec rspec spec/relaton/db_spec.rb

# Run a specific test by line number
bundle exec rspec spec/relaton/db_spec.rb:234

# Lint
bundle exec rubocop

# Lint with auto-fix
bundle exec rubocop -a
```

## Architecture

Relaton is a Ruby gem that fetches, caches, and manages bibliographic references to technical standards from 25+ organizations (ISO, IEC, IETF, NIST, IEEE, etc.).

### Plugin Registry Pattern

**Relaton::Registry** (singleton) auto-discovers and manages backend processor gems (relaton-iso, relaton-iec, relaton-ietf, etc.). Each processor implements the **Relaton::Processor** interface (`get`, `from_xml`, `from_yaml`, `grammar_hash`, `prefix`, `defaultprefix`). The registry routes reference codes to the correct processor by matching prefixes (e.g., "ISO 19115" → `:relaton_iso`).

### Db (lib/relaton/db.rb) — Main Public API

`Relaton::Db#fetch(ref, year, opts)` is the primary entry point. It:
1. Identifies the processor via Registry prefix matching
2. Handles combined references (`+` for derivedFrom, `,` for amendments) in `combine_doc`
3. Delegates to `check_bibliocache` which manages the dual-cache lookup and network fetch flow

`Relaton::Db#fetch_all(text, edition, year)` searches cached entries, filtering by text content (via `match_xml_text?`), edition, and/or year. Returns an array of deserialized bibliographic items from both local and global caches.

The dual-cache strategy uses a **global cache** (`~/.relaton/cache`) and an optional **local cache** (project-level). `check_bibliocache` checks local first, falls back to global, and syncs between them.

### DbCache (lib/relaton/db_cache.rb) — File-based Storage

Stores entries as files under `{dir}/{prefix}/{filename}.{ext}` (e.g., `testcache/iso/iso_19115-1.xml`). Key behaviors:
- Cache keys are wrapped like `ISO(ISO 19115-1:2014)` and converted to filenames via regex
- Entries can be XML, "not_found {date}", or "redirection {target_key}"
- Undated references expire after 60 days; dated ones persist indefinitely
- Version tracking per prefix directory invalidates cache when processor grammar changes
- File locking (`LOCK_EX`) for thread-safe concurrent writes

### WorkersPool (lib/relaton/workers_pool.rb)

Thread pool for `fetch_async`. Default 10 threads per processor, overridable via `RELATON_FETCH_PARALLEL` env var.

### Cache Key Format

`std_id` builds keys like `ISO(ISO 19115-1:2014 (all parts) after-2020-01-01)`. The filename regex in `db_cache.rb` uses `[^)]+` — suffixes use `-` not parentheses to avoid breaking it.

## Testing

- RSpec with VCR cassettes in `spec/vcr_cassetes/` for recorded HTTP interactions
- Tests create `testcache`/`testcache2` directories and clean them in `before(:each)`
- Cache-related tests need `<fetched>` elements in XML for `valid_entry?` to return true
- Integration tests in `spec/relaton_spec.rb`; unit tests mirror `lib/` structure under `spec/relaton/`

## Style

- RuboCop config inherits from [Ribose OSS guides](https://github.com/riboseinc/oss-guides), target Ruby 3.2
- Thread safety via `@semaphore` (Mutex) around cache reads/writes in Db
