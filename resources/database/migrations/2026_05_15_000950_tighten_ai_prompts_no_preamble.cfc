/**
 * Tighten the three Phase 4 system prompts so the model does not
 * emit "thinking" text before the JSON. Real-world output on
 * reasoning models prefixes the JSON with prose like "Let me
 * think... Wait, I should follow my instructions and respond with
 * JSON..." which the agent UI then displayed verbatim.
 *
 * Idempotent: only patches rows that still hold the originally
 * seeded prompt (detected by a substring marker). Operator-edited
 * prompts are left alone, preserving the admin's customizations.
 */
component {

    function up( schema, qb ){
        patch( "suggested-reply",
               "Output format (strict):",
               "Output format (strict, NO preamble):" & chr( 10 )
               & "DO NOT explain your reasoning. DO NOT think out loud. DO NOT acknowledge these instructions." & chr( 10 )
               & "Your entire response must be a single valid JSON object. The very first character is { and the very last character is }." & chr( 10 ) );

        patch( "triage",
               "Output format (strict):",
               "Output format (strict, NO preamble):" & chr( 10 )
               & "DO NOT explain your reasoning. DO NOT think out loud. DO NOT acknowledge these instructions." & chr( 10 )
               & "Your entire response must be a single valid JSON object. The very first character is { and the very last character is }." & chr( 10 ) );

        patch( "thread-summary",
               "Output format (strict):",
               "Output format (strict, NO preamble):" & chr( 10 )
               & "DO NOT explain your reasoning. DO NOT think out loud. DO NOT acknowledge these instructions." & chr( 10 )
               & "Your entire response must be a single valid JSON object. The very first character is { and the very last character is }." & chr( 10 ) );
    }

    function down( schema, qb ){
        // No-op. The original prompt strings are still seeded by the
        // earlier migrations; reverting individual phrase changes is
        // not worth the maintenance burden.
    }

    private void function patch( required string featureKey, required string findText, required string replaceText ){
        var rows = queryExecute(
            "SELECT system_prompt FROM ai_system_prompts WHERE feature_key = :k",
            { k : arguments.featureKey }
        );
        if ( !rows.recordCount ) return;
        var current = rows.system_prompt[ 1 ];
        if ( !len( current ) || findNoCase( arguments.findText, current ) == 0 ) return;
        var updated = replaceNoCase( current, arguments.findText, arguments.replaceText, "one" );
        queryExecute(
            "UPDATE ai_system_prompts
             SET    system_prompt = :p,
                    updated_at    = NOW()
             WHERE  feature_key   = :k",
            { p : updated, k : arguments.featureKey }
        );
    }

}
