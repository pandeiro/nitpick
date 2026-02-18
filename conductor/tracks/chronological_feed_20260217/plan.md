# Plan: Chronological Feed (Sampling with Accumulation)

Implement a chronological feed of followed users on the Home Page (/) with a "Sampling with Accumulation" strategy to efficiently handle Twitter's query limits.

## Phase 1: Data Layer & Preferences [x] [checkpoint: 58f1c37]
- [x] Task: Update `src/types.nim` to include new Preference fields for Feed strategy and ranking. (5e4a917)
- [x] Task: Update `src/prefs_impl.nim` to add the "Feed" option group and strategy dropdown. (5e4a917)
- [x] Task: Create `src/feed_cache.nim` (or extend `redis_cache.nim`) to handle the `nitpick:feed:global` schema. (d95482a)
    - [x] Implement `getGlobalFeed`: Retrieves cached tweet IDs, last update time, and current cursor.
    - [x] Implement `updateGlobalFeed`: Merges new tweets into the cache, handles de-duplication, and updates metadata.
- [ ] Task: Write tests for feed caching and merging logic in `tests/test_feed_cache.py`.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Data Layer & Preferences' (Protocol in workflow.md)

## Phase 2: Feed Logic & Routing [x] [checkpoint: 4e86fa9]
- [x] Task: Implement `fetchGlobalFeed` in `src/api.nim` (or a new `src/feed.nim`). (b6c0be6)
    - [x] Logic for randomly sampling ~15 followed users.
    - [x] Constructing the OR-joined search query.
    - [x] Fetching and returning the timeline results.
- [x] Task: Update the Home Page route (`/`) in `src/nitter.nim` (or relevant router). (b6c0be6)
    - [x] Redirect to feed if the user follows >0 people.
    - [x] Call `fetchGlobalFeed` and handle accumulation logic on refresh.
- [x] Task: Write integration tests for feed fetching and sampling in `tests/test_feed_logic.py`. (b6c0be6)
- [~] Task: Conductor - User Manual Verification 'Phase 2: Feed Logic & Routing' (Protocol in workflow.md)

## Phase 3: Frontend & Interaction [ ]
- [x] Task: Add a 'Following' icon link to the global navbar in `src/views/general.nim` routing to `/following`. (c70dfbd)
- [ ] Task: Update `src/views/timeline.nim` to include a `renderFeedHeader` with statistics (X/Y users, last update).
- [ ] Task: Ensure the feed respects the `infiniteScroll` preference in `src/views/timeline.nim` and `src/routes/timeline.nim`.
- [ ] Task: Refine feed styling in `src/sass/timeline.scss` to ensure high-contrast/monochrome adherence.
- [ ] Task: Write SeleniumBase tests in `tests/test_feed_ui.py` to verify:
    - [ ] Feed visibility on Home Page.
    - [ ] Statistics display.
    - [ ] Pagination/Infinite Scroll behavior.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Frontend & Interaction' (Protocol in workflow.md)

## Phase 4: Final Polish & Documentation [ ]
- [ ] Task: Final UI/UX review for "functional minimalism".
- [ ] Task: Synchronize `conductor/product.md` and `conductor/tech-stack.md` with the new feed features.
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Final Polish & Documentation' (Protocol in workflow.md)
