# Spec: Chronological Feed (Sampling with Accumulation)

## Overview
Implement a chronological feed of all followed users on the Home Page (/). This includes a "Sampling with Accumulation" strategy to handle Twitter's query limits and a new "Feed" settings group.

## Functional Requirements
1. **Home Page (/)**: Displays the chronological feed of followed users.
   - If the user follows no one, display the default landing page.
2. **Sampling with Accumulation Strategy**:
   - **Initial Fetch/Refresh**: Randomly sample up to 15 users from the follow list. Fetch their latest tweets via Twitter search.
   - **Merging**: Merge fetched tweets with the existing cached global feed.
   - **De-duplication & Sorting**: Ensure all tweets are unique and sorted chronologically (by ID/timestamp descending).
   - **Feed Cache**: Store the merged result (Tweet IDs) in Redis (`nitpick:feed:global`) with a 15-minute TTL.
   - **Discoverability**: Manual refreshes sample different users, gradually expanding the feed's "coverage" of the follow list.
3. **Pagination**:
   - Use the cursor from the *most recent* fetch for "Load more" or infinite scroll.
   - Obey the user's `infiniteScroll` preference for the feed.
4. **Feed Statistics**:
   - Display `Showing tweets from X/Y followed users. Last updated: Z` in the feed header.
5. **Settings Integration**:
   - Add "Feed" option group to Preferences.
   - Add "Multi-user Feed Strategy" dropdown: [Sampling (default), Sequential (Future)].
6. **Caching**:
   - **Global Feed Cache**: Redis key `nitpick:feed:global` stores serialized tweet IDs and metadata (last sampled users, timestamp, current cursor).
   - **Tweet Cache**: Utilize existing `cache` proc for individual tweets.

## Non-Functional Requirements
- **Minimalism**: High-contrast/monochrome UI, no instructional clutter.
- **Performance**: Low latency on Home Page; efficient Redis operations for merging/sorting.

## Acceptance Criteria
- Home Page displays a feed of followed users.
- Refetching sampled users on refresh works and merges into the view.
- Infinite scroll works if enabled in preferences.
- Settings correctly toggle the feed strategy.
- SeleniumBase tests verify feed loading, statistics display, and pagination.

## Out of Scope
- Algorithmic ranking (ranking algorithm placeholder in settings, functionality strictly chrono).
- Sequential fetching strategy implementation.
