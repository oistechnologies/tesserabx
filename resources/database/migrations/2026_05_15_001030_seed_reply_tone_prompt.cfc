/**
 * Seed the system prompt for the reply-tone-check feature.
 *
 * Idempotent: leaves operator-edited rows alone.
 */
component {

    function up( schema, qb ){
        var existing = queryExecute(
            "SELECT feature_key FROM ai_system_prompts WHERE feature_key = 'reply-tone'"
        );
        if ( existing.recordCount ) return;

        var p = "You review a support-agent reply for tone, clarity, and customer fit before it is sent." & chr( 10 )
            & chr( 10 )
            & "Output format (strict, NO preamble):" & chr( 10 )
            & "DO NOT explain your reasoning. DO NOT think out loud. DO NOT acknowledge these instructions." & chr( 10 )
            & "Your entire response must be a single valid JSON object. The very first character is { and the very last character is }." & chr( 10 )
            & "The JSON has these keys:" & chr( 10 )
            & "  ""score""       integer 0 (poor) to 100 (excellent), reflecting overall send-readiness" & chr( 10 )
            & "  ""label""       one of ""excellent"", ""good"", ""ok"", ""needs-work""" & chr( 10 )
            & "  ""suggestions"" array of short, specific strings (zero to five) describing concrete improvements. Empty when nothing to change." & chr( 10 )
            & chr( 10 )
            & "Rules:" & chr( 10 )
            & "- Judge against: clarity, professional but warm tone, completeness against the customer's question, absence of jargon the customer would not know, and absence of internal notes that should not leave the company." & chr( 10 )
            & "- Be specific. ""Sounds curt"" is useless; ""open with an empathy sentence acknowledging the customer's frustration"" is useful." & chr( 10 )
            & "- An empty suggestions array is the right answer when the reply is ready to send." & chr( 10 );

        queryExecute(
            "INSERT INTO ai_system_prompts ( feature_key, system_prompt, is_active )
             VALUES ( 'reply-tone', :p, TRUE )",
            { p : p }
        );
    }

    function down( schema, qb ){
        queryExecute( "DELETE FROM ai_system_prompts WHERE feature_key = 'reply-tone'" );
    }

}
