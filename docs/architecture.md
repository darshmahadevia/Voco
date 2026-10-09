# Voco desktop architecture

The current app is Electron with a React, TypeScript, and Motion interface. Electron main owns windows, the menu-bar icon, and the lifetime of a bundled macOS helper. The helper owns Moonshine Medium Streaming, audio capture, permissions, global shortcuts, session identity, and safe text insertion.

The renderer uses a narrow preload API to read state and send validated commands. It receives no audio buffers or filesystem access. Native model downloads begin only after the user chooses **Download speech model** in setup. Models stay in Application Support across app updates.

The shared state and command contract lives in `app/shared/protocol.ts`. The native coordinator publishes complete snapshots. Model state, permission state, and dictation state remain separate. A granted Keyboard access permission can coexist with an unavailable shortcut monitor and therefore needs a restart action.

The existing focus-validation and live-writer implementations remain the safety boundary for other apps. They reject password fields, changed focus, document edits, and caret changes. Writable native fields receive provisional corrections within Voco's owned range. Readable web and Electron fields with writable selection ranges receive tagged Unicode keyboard events, in small batches verified against the expected document and caret. The shortcut monitor ignores these events. They leave the clipboard untouched and deliver the editor's input handlers. Uncertain writes stop with recovery rather than retrying a partial insertion as paste. Initial nonempty selections remain selected, with insertion after their end. Committing a pause moves the owned insertion boundary forward without losing that selection. Buffered fallback checks its original document and selection before clipboard-preserving paste. Session IDs reject late recognition results after cancellation.

Ordinary pill updates contain status, not transcript previews. Recovery contains copyable words. Transcript retention is memory-only. A platform-specific helper can later replace the macOS helper while preserving the Electron interface and the process contract.

See [the migration design and alternatives](migration/architecture.md). [The predecessor architecture](migration/pre-electron-architecture.md) records the original Apple SpeechAnalyzer implementation and its insertion/permission fixes.

The listening protocol includes `text` independently of `lastTranscript`. Disabling transcript retention does not hide partial words during a session. The pill displays the latest words and exposes the full current transcript in its title. Polling and pause commits serialize editor updates. Stop waits for an in-flight editor update before finalizing Moonshine; cancellation invalidates the session and prevents later chunks from writing. A posted keyboard event drains before cancellation restores an unchanged original selection.
