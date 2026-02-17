# Implementation Plan: Pinned Tweets

## Phase 1: Backend & Data Layer
- [x] Task: Define Redis storage schema and helper functions for pinned tweets. (6fdc0fa)
    - [x] Create `src/routes/pinned.nim` for pinning logic.
    - [x] Implement `addPinnedTweet` and `removePinnedTweet` in a new or existing utility file.
    - [x] Write integration tests for pinning/unpinning logic using Python.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Backend & Data Layer' (Protocol in workflow.md)

## Phase 2: Frontend Implementation
- [ ] Task: Add "Pin" button to the tweet component.
    - [ ] Modify `src/views/tweet.nim` to include the Pin icon/interaction.
    - [ ] Add SCSS for the subtle Pin button in `src/sass/tweet/`.
- [ ] Task: Create the Pinned Tweets archive view.
    - [ ] Implement `src/views/pinned.nim` using Karax with a modernized aesthetic.
    - [ ] Register the `/pinned` route in `src/nitter.nim`.
    - [ ] Add SCSS for the modernized gallery view.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Frontend Implementation' (Protocol in workflow.md)

## Phase 3: Polish & Verification
- [ ] Task: Final UI/UX review against Product Guidelines.
    - [ ] Verify monochrome/high-contrast adherence.
    - [ ] Ensure gestural/subtle interactions for pinning.
- [ ] Task: Run full test suite to ensure no regressions.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Polish & Verification' (Protocol in workflow.md)
