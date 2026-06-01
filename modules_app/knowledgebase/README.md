# knowledgebase

Knowledge-base authoring, versioning, three-tier visibility, and the
inline-image pipeline.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and [docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Responsibility

Owns the `Article`, `ArticleVersion`, `ArticleFeedback`, and `Category`
entities plus the `kb_article_organizations` join. The public read
surface is served at `/kb` by the **portal** module (`portal:Kb`),
which is the single source of truth and renders markdown bodies to
HTML. This module declares no `entryPoint` of its own. Authoring lives
in `/agent/admin/kb` (the admin module) and category management in
`/agent/admin/kb/categories`; both call back through
`KnowledgebaseService`.

## Owned entities

- `Article` — title, slug, markdown `body`, `visibility`
  (public / organization / internal), `status` (draft / published),
  view count, author, timestamps. Postgres `search_vector` for
  full-text search and an optional pgvector `embedding`.
- `ArticleVersion` — a title/body snapshot taken on each publish.
- `ArticleFeedback` — helpful / not-helpful votes.
- `Category` — name, slug, self-referential `parent_id`, sort order.
- `kb_article_organizations` — the many-to-many join backing
  organization-scoped visibility (no Quick entity; raw SQL).

## Public service interface

`KnowledgebaseService` is the entry point other modules use.

- Categories: `listCategories`, `listCategoriesWithCounts`,
  `getCategoryById`, `getCategoryBySlug`, `createCategory`,
  `updateCategory`, `deleteCategory`. Deleting a category orphans its
  articles (category cleared) and re-roots its child categories; a
  category can never be its own parent. A starter set is seeded by
  migration `2026_05_31_000000_seed_kb_default_categories`.
- Article writes: `createArticle`, `updateArticle`, `publishArticle`,
  `unpublishArticle`, `deleteArticle`.
- Article reads: `getArticleById`, `getArticleBySlug`,
  `listVisibleArticles`, `canRead`, `recordView`.
- Organization mapping: `setArticleOrganizations`,
  `listOrganizationIdsForArticle`.
- Feedback: `submitFeedback`, `feedbackTotalsForArticle`.
- Dashboard widgets: `topArticlesByViews`, `topArticlesForViewer`,
  `draftsByCurrentAgent`.
- Embeddings (AI, optional): `saveEmbedding`, `searchByEmbedding`,
  `listArticlesNeedingEmbedding`.

`KbImageService` stores inline article images on the **public** cbfs
disk (`cbfsPublicProvider`) so they can be referenced directly from
`<img src>` in rendered markdown. `storeArticleImage` validates the
type (png, jpg, jpeg, gif, webp), enforces `KB_IMAGE_MAX_BYTES`
(default 5 MB), and sniffs the magic bytes before writing to
`kb/articles/<articleId>/<uuid>.<ext>`.

## Authoring (agent admin)

- The editor at `/agent/admin/kb` uses EasyMDE (self-hosted under
  `includes/vendor/easymde-2.20.0/`), wired with code-block
  highlighting in the preview, draft autosave, a server-side preview
  that calls `Kb.preview` (so the preview matches the public render
  exactly), drag/paste/toolbar image upload to `Kb.uploadImage`, and a
  Bootstrap-Icons toolbar (no Font Awesome dependency).
- The body is posted base64-encoded in a hidden `bodyB64` field and
  decoded server-side in `Kb.decodeBody`. This is required: the global
  cbantisamy request interceptor would otherwise collapse the body's
  newlines and encode its quotes. Same pattern as the custom-fields
  options field.

## Events emitted

- `onKbArticlePublished` — announced on publish; the `ai` module
  listens to compute an embedding when AI is enabled.

## Notes

- Bodies are markdown, rendered to HTML with the `markdown()` BIF on
  read (the portal show view and the editor preview endpoint).
- Article feedback voting is restricted to **logged-in contacts**.
  Anonymous visitors and agents see the aggregate helpful /
  not-helpful count but cannot vote.
