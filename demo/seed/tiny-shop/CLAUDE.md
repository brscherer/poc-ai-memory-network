# tiny-shop

Small shopping-cart library (Python 3, standard library only).
Run the tests with `python3 -m unittest -v`.

## Team memory

This repository shares a memory server with the rest of the team
(the `ai-memory` MCP tools). Other people work on this code from other
machines, and the decisions they make live in that memory, not in your chat.

- **Before you change code**, call `memory_briefing` with
  `settled_first: true` and read every page under `decisions/` that touches
  your task (`memory_read_page`). Follow them. If one looks wrong, say so to
  the user instead of silently diverging.
- **When the user and you settle a decision** (a convention, a data format,
  a library choice, a trade-off someone else would otherwise re-litigate),
  record it right away with `memory_write_page`:
  - `path`: `decisions/<short-kebab-slug>.md`
  - `pinned`: `true`, `tags`: `["decision"]`
  - body, in this shape:

    ```markdown
    # <Decision title>

    - Status: accepted
    - Date: <YYYY-MM-DD>
    - Decided by: <the user's name>

    ## Context
    ## Decision
    ## Consequences
    ```

  Search first (`memory_query`) and update an existing page rather than
  writing a duplicate.
- Omit `workspace` and `project` in these calls: the MCP bridge fills them in
  from this repository's `.ai-memory.toml`.
