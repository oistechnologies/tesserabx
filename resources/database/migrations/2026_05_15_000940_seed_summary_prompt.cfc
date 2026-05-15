/**
 * Seed the default system prompt for the thread-summary feature.
 *
 * Idempotent: leaves an operator-edited row alone.
 */
component {

    function up( schema, qb ){
        var existing = queryExecute(
            "SELECT feature_key FROM ai_system_prompts WHERE feature_key = 'thread-summary'"
        );
        if ( existing.recordCount ) return;

        var p = "You summarize support-ticket conversations for an agent who needs to get up to speed quickly." & chr( 10 )
            & chr( 10 )
            & "Output format (strict):" & chr( 10 )
            & "Respond with a single valid JSON object and nothing else. The JSON has these keys:" & chr( 10 )
            & "  ""summary""    a two to four sentence overview of what is happening on the ticket" & chr( 10 )
            & "  ""keyPoints""  an array of three to six short bullet strings covering the salient facts and decisions" & chr( 10 )
            & "  ""nextStep""   one short string describing the most useful next action the agent could take" & chr( 10 )
            & chr( 10 )
            & "Rules:" & chr( 10 )
            & "- Do not invent facts. If something is unclear in the thread, say so." & chr( 10 )
            & "- Skip greetings and pleasantries; focus on substance." & chr( 10 )
            & "- Do not wrap the JSON in markdown fences. Do not emit any text outside the JSON object.";

        queryExecute(
            "INSERT INTO ai_system_prompts ( feature_key, system_prompt, is_active )
             VALUES ( 'thread-summary', :p, TRUE )",
            { p : p }
        );
    }

    function down( schema, qb ){
        queryExecute( "DELETE FROM ai_system_prompts WHERE feature_key = 'thread-summary'" );
    }

}
