# Implementation Plan - JSON API via Content Negotiation

## Phase 1: Core Read-Only Endpoints [checkpoint: 6b391fd]
- [x] Task: Enable JSON for Home Feed (`GET /`) (47a24de)
    - [x] Write failing test: Verify `GET /` with `Accept: application/json` returns JSON structure matching `API_DESIGN.md`
    - [x] Implement: Add content negotiation to `nitter.nim` for home feed route
    - [x] Verify: Run tests
- [x] Task: Enable JSON for User Profile (`GET /<username>`) (d04530a)
    - [x] Write failing test: Verify `GET /<username>` returns JSON profile data
    - [x] Implement: Add content negotiation to `timeline.nim` for profile route
    - [x] Verify: Run tests
- [x] Task: Enable JSON for User Replies (`GET /<username>/with_replies`) (63d2bee)
    - [x] Write failing test: Verify `GET /<username>/with_replies` returns JSON
    - [x] Implement: Update route in `timeline.nim`
    - [x] Verify: Run tests
- [x] Task: Enable JSON for User Media (`GET /<username>/media`) (63d2bee)
    - [x] Write failing test: Verify `GET /<username>/media` returns JSON
    - [x] Implement: Update route in `timeline.nim`
    - [x] Verify: Run tests
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Core Read-Only Endpoints' (Protocol in workflow.md)

## Phase 2: Discovery & Search
- [x] Task: Enable JSON for Search (`GET /search`) (b51354b)
    - [x] Write failing test: Verify `GET /search` returns JSON results
    - [x] Implement: Update `search.nim`
    - [x] Verify: Run tests
- [ ] Task: Enable JSON for Following Lists (`GET /following`)
    - [ ] Write failing test: Verify `GET /following` returns JSON list structure
    - [ ] Implement: Update `follow.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for List Profile (`GET /i/lists/<id>`)
    - [ ] Write failing test: Verify `GET /i/lists/<id>` returns JSON
    - [ ] Implement: Update `list.nim`
    - [ ] Verify: Run tests
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Discovery & Search' (Protocol in workflow.md)

## Phase 3: User Content & Actions
- [ ] Task: Enable JSON for Single Tweet (`GET /<username>/status/<id>`)
    - [ ] Write failing test: Verify `GET /<username>/status/<id>` returns JSON tweet details
    - [ ] Implement: Update `status.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for Pinned Tweets (`GET /pinned`)
    - [ ] Write failing test: Verify `GET /pinned` returns JSON
    - [ ] Implement: Update `pinned.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for User Lists (`GET /<username>/lists`)
    - [ ] Write failing test: Verify `GET /<username>/lists` returns JSON
    - [ ] Implement: Update `list.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for Follow Actions (`POST /follow`, `POST /unfollow`)
    - [ ] Write failing test: Verify POST actions return JSON response/redirect
    - [ ] Implement: Update `follow.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for Pin Actions (`POST /pin`, `POST /unpin`)
    - [ ] Write failing test: Verify POST actions return JSON response/redirect
    - [ ] Implement: Update `pinned.nim`
    - [ ] Verify: Run tests
- [ ] Task: Conductor - User Manual Verification 'Phase 3: User Content & Actions' (Protocol in workflow.md)

## Phase 4: List Management
- [ ] Task: Enable JSON for List Management Actions (`POST /lists/*`)
    - [ ] Write failing test: Verify create, delete, rename, add/remove member actions return JSON
    - [ ] Implement: Update `follow.nim`
    - [ ] Verify: Run tests
- [ ] Task: Enable JSON for List Members (`GET /i/lists/<id>/members`)
    - [ ] Write failing test: Verify `GET /i/lists/<id>/members` returns JSON
    - [ ] Implement: Update `list.nim`
    - [ ] Verify: Run tests
- [ ] Task: Conductor - User Manual Verification 'Phase 4: List Management' (Protocol in workflow.md)
