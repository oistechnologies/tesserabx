/**
 * Create ai_system_prompts: admin-editable system-prompt templates,
 * one per AI feature key.
 *
 * Each AI feature reads its template from here, substitutes any
 * `{{placeholder}}` tokens, and sends it as the system message in
 * the bx-ai call. Phase 5's admin UI exposes a CRUD surface; this
 * migration seeds the Phase 4b defaults so a fresh install behaves
 * sensibly out of the box.
 *
 * `feature_key` is the primary key so callers can do
 * `SELECT system_prompt FROM ai_system_prompts WHERE feature_key = ?`
 * without ambiguity.
 *
 * Not tenant-scoped: provider configuration, not customer data.
 */
component {

    function up( schema, qb ){
        schema.create( "ai_system_prompts", function( table ){
            table.string( "feature_key", 64 ).primaryKey();
            table.text(   "system_prompt" );
            table.boolean( "is_active" ).default( true );
            table.timestamp( "created_at" ).default( "CURRENT_TIMESTAMP" );
            table.timestamp( "updated_at" ).default( "CURRENT_TIMESTAMP" );
        } );

        // Seed the suggested-reply default. The {{agentName}} token
        // is substituted at call time. The JSON output contract keeps
        // agent-facing notes out of the customer-visible reply (the
        // failure mode reported on the first real test run).
        var defaultPrompt = "You are an experienced customer support agent drafting a reply on behalf of {{agentName}}." & chr( 10 )
            & chr( 10 )
            & "Tone and behaviour:" & chr( 10 )
            & "- Professional, clear, and friendly. Match the formality of the customer." & chr( 10 )
            & "- Address the customer's most recent message directly. Do not invent facts." & chr( 10 )
            & "- If information is missing, ask one focused follow-up question." & chr( 10 )
            & "- Keep the reply to two to six sentences unless the situation clearly needs more." & chr( 10 )
            & "- Sign off as {{agentName}} when the closing fits naturally." & chr( 10 )
            & chr( 10 )
            & "Output format (strict):" & chr( 10 )
            & "You MUST respond with a single valid JSON object and nothing else." & chr( 10 )
            & "The JSON has two keys:" & chr( 10 )
            & "  ""reply""  the message that will be sent to the customer. No prefatory remarks, no agent-facing notes." & chr( 10 )
            & "  ""notes""  optional. Anything ONLY the agent should see (caveats, urgency, missing context, suggested follow-ups). Empty string if nothing to note." & chr( 10 )
            & chr( 10 )
            & "Do not wrap the JSON in markdown fences. Do not emit any text outside the JSON object.";

        queryExecute(
            "INSERT INTO ai_system_prompts ( feature_key, system_prompt, is_active )
             VALUES ( :k, :p, TRUE )",
            { k : "suggested-reply", p : defaultPrompt }
        );
    }

    function down( schema, qb ){
        schema.drop( "ai_system_prompts" );
    }

}
