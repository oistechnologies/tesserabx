## Authoring a knowledge-base article

Knowledge-base articles are written by agents and published either publicly, to specific organizations, or as internal-only notes for the support team.

### Drafting

Open **Knowledge base** under /agent/admin and click **New article**. The editor supports markdown plus a preview pane. Pick a category and a visibility tier before saving the first draft.

### Visibility tiers

| Tier                   | Who reads it                                              |
| ---------------------- | --------------------------------------------------------- |
| `public`               | Anyone, including anonymous visitors to the portal.        |
| `organization-scoped`  | Signed-in contacts whose organization has been granted access. |
| `internal`             | Agents only. Never reaches client surfaces.                |

### Publishing

A draft has no client-visible footprint. Click **Publish** to make the article live; the system stamps the version, indexes the article for search (and for AI semantic search when AI is on), and notifies the team channel if configured.

### Editing a published article

Every edit to a published article creates a new version. The history is visible via the **Versions** tab; you can roll back to a previous version at any time. The published-vs-draft distinction is preserved so you can stage edits without changing what readers see.
