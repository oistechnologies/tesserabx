/**
 * B9: AI-driven escalation-risk scoring per ticket.
 *
 * Adds three columns to tickets:
 *   - escalation_risk_score      : smallint 0-100 (NULL when unscored)
 *   - escalation_risk_rationale  : the model's short explanation
 *   - escalation_risk_at         : when the score was last computed
 *
 * EscalationRiskService writes these on ticket create + status change;
 * the right-column ticket panel reads them. The columns are NULLable
 * because AI is optional and a ticket can live its whole life unscored.
 */
component {

    function up( schema, qb ){
        schema.alter( "tickets", function( table ){
            table.addColumn( table.smallInteger( "escalation_risk_score" ).nullable() );
            table.addColumn( table.text( "escalation_risk_rationale" ).nullable() );
            table.addColumn( table.timestamp( "escalation_risk_at" ).nullable() );
        } );
    }

    function down( schema, qb ){
        schema.alter( "tickets", function( table ){
            table.dropColumn( "escalation_risk_score" );
            table.dropColumn( "escalation_risk_rationale" );
            table.dropColumn( "escalation_risk_at" );
        } );
    }

}
