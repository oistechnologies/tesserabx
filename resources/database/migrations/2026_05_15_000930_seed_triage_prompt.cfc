/**
 * Seed the default system prompt for the triage feature.
 *
 * Idempotent: if a row already exists for feature_key = 'triage'
 * (operator edited it via the admin UI), we leave it alone.
 */
component {

    function up( schema, qb ){
        var existing = queryExecute(
            "SELECT feature_key FROM ai_system_prompts WHERE feature_key = 'triage'"
        );
        if ( existing.recordCount ) return;

        var p = "You are a support-desk triage assistant. Read the incoming ticket and classify it." & chr( 10 )
            & chr( 10 )
            & "Output format (strict):" & chr( 10 )
            & "Respond with a single valid JSON object and nothing else. The JSON has these keys:" & chr( 10 )
            & "  ""priority""   one of ""low"", ""normal"", ""high"", ""urgent""" & chr( 10 )
            & "  ""ticketType"" one of ""incident"", ""request"", ""problem"", ""question""" & chr( 10 )
            & "  ""tags""       an array of 0 to 5 short, lower-case tag names (single words or hyphenated, e.g. ""password-reset"", ""billing"")" & chr( 10 )
            & "  ""sentiment""  one of ""positive"", ""neutral"", ""negative""" & chr( 10 )
            & "  ""rationale""  one short sentence explaining the priority choice" & chr( 10 )
            & chr( 10 )
            & "Rules:" & chr( 10 )
            & "- Default to ""normal"" priority unless the message clearly indicates outage, blocked work, data loss, or urgent escalation." & chr( 10 )
            & "- Tags should describe the topic, not the sentiment. Reuse common tags across similar tickets." & chr( 10 )
            & "- Do not wrap the JSON in markdown fences. Do not emit any text outside the JSON object.";

        queryExecute(
            "INSERT INTO ai_system_prompts ( feature_key, system_prompt, is_active )
             VALUES ( 'triage', :p, TRUE )",
            { p : p }
        );
    }

    function down( schema, qb ){
        queryExecute( "DELETE FROM ai_system_prompts WHERE feature_key = 'triage'" );
    }

}
