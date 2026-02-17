# Specification: Pinned Tweets Personal Archive

## Goal
Implement a local-only feature that allows users to "pin" (archive) specific tweets. These tweets will be stored in the local Redis instance and can be viewed in a dedicated, modernized section of the Nitpick UI.

## Requirements
- **Persistence:** Save tweet data (ID, content, author, etc.) to Redis.
- **Backend:** 
    - API endpoint/logic to add a tweet to the "pinned" set.
    - API endpoint/logic to remove a tweet from the "pinned" set.
    - Logic to retrieve all pinned tweets.
- **Frontend:**
    - A subtle "Pin" icon/button on each tweet (visible on hover).
    - A dedicated "/pinned" route to view the archive.
    - A modernized, monochrome/high-contrast UI for the pinned tweets gallery.
- **Privacy:** Data is stored only in the user's local Redis instance.

## Technical Details
- **Redis Key Structure:** Suggest using a Set or List under a key like `nitpick:pinned_tweets`.
- **Data Format:** Store the full JSON representation or a reference to the cached tweet if available.
- **UI Interaction:** Use Karax for the new views and SCSS for styling the modernized components.
