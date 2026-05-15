/**
 * Seed the system prompt for the post-resolution KB drafting feature.
 *
 * Idempotent: leaves an operator-edited row alone.
 *
 * The draft is created internal + unpublished per the build plan;
 * the prompt explicitly asks the model to write for an internal
 * audience and to flag anything that should not be exposed to
 * customers without scrubbing.
 */
component {

    function up( schema, qb ){
        var existing = queryExecute(
            "SELECT feature_key FROM ai_system_prompts WHERE feature_key = 'kb-draft'"
        );
        if ( existing.recordCount ) return;

        var p = "You draft a knowledge-base article from a resolved support-ticket conversation." & chr( 10 )
            & chr( 10 )
            & "Output format (strict, NO preamble):" & chr( 10 )
            & "DO NOT explain your reasoning. DO NOT think out loud. DO NOT acknowledge these instructions." & chr( 10 )
            & "Your entire response must be a single valid JSON object. The very first character is { and the very last character is }." & chr( 10 )
            & "The JSON has these keys:" & chr( 10 )
            & "  ""title""      a short, search-friendly title (under 80 characters)" & chr( 10 )
            & "  ""body""       the article body in markdown. Three to eight short sections: problem, cause, solution, optionally prerequisites, related links, gotchas." & chr( 10 )
            & "  ""summary""    a one-sentence summary suitable for a card preview" & chr( 10 )
            & "  ""warnings""   an array of strings flagging anything the human author should scrub before publishing (customer names, ticket-specific identifiers, internal-only context). Empty array if nothing to flag." & chr( 10 )
            & chr( 10 )
            & "Rules:" & chr( 10 )
            & "- The audience is a support agent or technician. Use plain, direct language." & chr( 10 )
            & "- Generalize beyond the specific ticket: write the article as if the same problem could affect any customer." & chr( 10 )
            & "- Do not invent steps the conversation did not contain. If the resolution is unclear, say so in warnings." & chr( 10 )
            & "- Strip greetings, sign-offs, and customer-specific identifiers from the body. Flag any that you find via warnings." & chr( 10 );

        queryExecute(
            "INSERT INTO ai_system_prompts ( feature_key, system_prompt, is_active )
             VALUES ( 'kb-draft', :p, TRUE )",
            { p : p }
        );
    }

    function down( schema, qb ){
        queryExecute( "DELETE FROM ai_system_prompts WHERE feature_key = 'kb-draft'" );
    }

}
