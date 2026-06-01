/**
 * Seed a starter set of knowledge-base categories.
 *
 * Gives a fresh install a usable Category dropdown on the article
 * editor. Idempotent: each row is inserted only when its slug is not
 * already present, so re-running (or running after an admin has added
 * their own) is safe. Admins can rename, reparent, reorder, or delete
 * these through /agent/admin/kb/categories.
 *
 * queryExecute runs without an explicit datasource so it uses the
 * migration runner's connection (the same pattern as the other seed
 * migrations; passing a name throws "available datasource names are
 * [cfmigrations]"). kb_categories.id is VARCHAR(36), so the id binds
 * as a plain string; only sort_order needs cast(... as integer)
 * because the JDBC binder sends every param as varchar.
 */
component {

    function up( schema, qb ) {
        var categories = [
            { name : "Getting Started",   slug : "getting-started", sortOrder : 10 },
            { name : "Account & Billing", slug : "account-billing", sortOrder : 20 },
            { name : "Troubleshooting",   slug : "troubleshooting", sortOrder : 30 },
            { name : "How-To Guides",     slug : "how-to-guides",   sortOrder : 40 },
            { name : "FAQ",               slug : "faq",             sortOrder : 50 },
            { name : "Release Notes",     slug : "release-notes",   sortOrder : 60 }
        ];

        for ( var cat in categories ) {
            queryExecute(
                "
                    INSERT INTO kb_categories ( id, name, slug, sort_order, created_at, updated_at )
                    SELECT :id, :name, :slug, cast( :sortOrder as integer ), now(), now()
                    WHERE NOT EXISTS ( SELECT 1 FROM kb_categories WHERE slug = :slug )
                ",
                {
                    id        : createObject( "java", "java.util.UUID" ).randomUUID().toString(),
                    name      : cat.name,
                    slug      : cat.slug,
                    sortOrder : cat.sortOrder
                }
            );
        }
    }

    function down( schema, qb ) {
        queryExecute(
            "
                DELETE FROM kb_categories
                WHERE slug IN (
                    'getting-started', 'account-billing', 'troubleshooting',
                    'how-to-guides', 'faq', 'release-notes'
                )
            "
        );
    }

}
