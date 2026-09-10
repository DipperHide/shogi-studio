# Interactive course contract (schema 1)

Each book lives in `godot/courses/hanyu-intro.json` or `hanyu-opening.json`. Authored Chinese teaching text is based on the supplied EPUB; source pages are zero-based EPUB image indices (printed page is usually index minus one). Never mark an OCR guess or an unchecked diagram as verified.

Top level: `schema: 1`, `id`, `title`, `source_sha256`, `page_count: 227`, `chapters: []`, `coverage: []`.
Chapter: `id`, `title`, `pages: [indices]`, `lessons: []`.
Lesson: `id`, `title`, `pages: [indices]`, `summary`, `steps: []`.
Each step has `kind`, `prompt` (or `body` for text), optional `source_pages`, and `explanation` for interactive steps.

- `text`: `body`.
- `choice`: `prompt`, `options: [strings]`, `answer: integer` (zero based), `explanation`.
- `move`: `prompt`, `position: SFEN string`, `accepted: [USI moves]`, optional `reply: [USI moves]`, `explanation`. Each accepted move is an alternative from the initial position. Replies execute after any accepted answer.
- `targets`: `prompt`, `position: SFEN string`, `from: USI square`, `targets: [USI squares]`, `explanation`. Learner selects the complete set, then submits. Target questions may concern geometrical attacks rather than legal moves; the prompt must specify which.
- `sequence`: `prompt`, `position: SFEN string or "startpos"`, `moves: [USI strings]`, `student_side: 1, -1, or 0` (0 means learner plays both sides), `explanation`. Opponent moves are automatic and the learner must play every assigned move; the answer may be revealed explicitly.

Positions use 81 squares and normal SFEN. Partial diagrams omit kings and irrelevant pieces. Tutorial-only Rules subclass tolerates absent kings and preserves subclass in copy; never weaken production game legality. Moves still enforce movement, ownership, drops, nifu, promotion and check when king is present. A missing king must not be rendered or silently invented. Full board coordinates must match source labels, including cropped diagrams. `targets` can illustrate occupied attack squares if clearly explained.

Coverage: one object per source page: `page`, `status` (`authored_verified`, `noninstructional_verified`, `pending`, or `draft`), `lesson_ids: [strings]`, `note`. Verified instructional pages need mapped lessons that cover their teaching, examples and exercises, not a generic repeated quiz. Noninstructional may cover colophon, blank pages, purely decorative covers; prefaces, etiquette, columns and glossary are instructional when they teach something. Record any omitted content honestly in coverage. Optionally add diagram IDs to steps for traceability.

Runtime agent owns only NEW `godot/scripts/shogi_tutorial*.gd`, NEW `godot/tests/tutorial*.gd`, and its test runner. Root owns shared app/menu/export/catalog edits. Runtime entry: RefCounted controller with `initialize(menu)` and `show_catalog()`, using `menu._page`, `menu.button`, `menu.label`, `menu.app.palette()` and font. Tutorial owns an independent board, never changes the active game/session, progress persists separately. Show pending coverage clearly; do not claim a book complete unless coverage proves it. No raw scan reader as a substitute. Support retry, honest reveal vs mastered progress, resume, reset, review mistakes, chapter/lesson navigation, small portrait touch layout. Sources remain local and are not copied into public builds.

Content agents each own their assigned book JSON and any uniquely named authoring scripts/reports. They may share source files read-only. All accepted moves/sequences must be checked against rules; visual source inspection is required for diagram transcription. No shared app/runtime edits. Report source coverage counts and unresolved pages truthfully.
