/**
 * agent-dashboard.js — drag/drop reorder, hide/restore, periodic poll
 * for the /agent home dashboard.
 *
 * The home view emits a single <div id="agent-dashboard"> wrapper
 * carrying the endpoint URLs as data-attributes. Each widget card is
 * a child div with [data-widget-id]. The script:
 *
 *   - Initializes a Sortable on the wrapper, posts the new order on
 *     drop end.
 *   - Listens for clicks on .hide-widget / .restore-widget /
 *     .reset-dashboard buttons and posts the corresponding action.
 *   - On a fixed interval (data-poll-interval, default 30s), fetches
 *     the poll endpoint and calls
 *       window.tbxDashboard.widgets[<id>].update(payload, card)
 *     for every widget that has a registered updater. Widget partials
 *     register their updaters during the initial render.
 *
 * Skipped when the tab is hidden (document.visibilityState === 'hidden')
 * to match the bell-poll behavior in the agent layout.
 */
(function(){
    "use strict";

    var ROOT_ID = "agent-dashboard";

    function $root(){
        return document.getElementById( ROOT_ID );
    }

    // Widgets register their updaters here from inside their partials:
    //   window.tbxDashboard = window.tbxDashboard || { widgets: {} };
    //   window.tbxDashboard.widgets[ "agent-home.my-open-tickets" ] = {
    //       update: function( payload, card ){ ... }
    //   };
    window.tbxDashboard = window.tbxDashboard || { widgets: {} };

    /**
     * POST a form-encoded body. ColdBox doesn't auto-deserialize JSON
     * request bodies into `rc` and the project's other AJAX endpoints
     * (notifications, ticket actions) all use form-encoded too, so we
     * match that here. Arrays are flattened to comma-delimited strings,
     * which the handler's `parseOrderList` accepts.
     */
    function postForm( url, body ){
        var params = new URLSearchParams();
        Object.keys( body || {} ).forEach( function( k ){
            var v = body[ k ];
            if ( Array.isArray( v ) ) {
                params.append( k, v.join( "," ) );
            } else if ( typeof v === "boolean" ) {
                params.append( k, v ? "true" : "false" );
            } else if ( v !== null && v !== undefined ) {
                params.append( k, String( v ) );
            }
        } );
        return fetch( url, {
            method      : "POST",
            headers     : {
                "Content-Type" : "application/x-www-form-urlencoded",
                "Accept"       : "application/json"
            },
            body        : params.toString(),
            credentials : "same-origin"
        } );
    }

    function initSortable( root ){
        if ( typeof Sortable === "undefined" ) {
            console.warn( "[agent-dashboard] Sortable not loaded; drag-and-drop disabled" );
            return;
        }
        Sortable.create( root, {
            handle      : ".drag-handle",
            animation   : 150,
            ghostClass  : "agent-dashboard-ghost",
            forceFallback : true,
            onEnd : function(){
                var ids = [];
                root.querySelectorAll( "[data-widget-id]" ).forEach( function( el ){
                    ids.push( el.getAttribute( "data-widget-id" ) );
                } );
                var url = root.getAttribute( "data-save-order-url" );
                if ( !url ) return;
                postForm( url, { order : ids } ).then( function( res ){
                    if ( !res.ok ) {
                        console.warn( "[agent-dashboard] order save rejected:", res.status );
                    }
                } ).catch( function( e ){
                    console.warn( "[agent-dashboard] order save failed:", e );
                } );
            }
        } );
    }

    function initHideRestoreReset( root ){
        var hideUrl  = root.getAttribute( "data-save-hidden-url" );
        var resetUrl = root.getAttribute( "data-reset-url" );

        // Hide a single widget.
        root.addEventListener( "click", function( evt ){
            var btn = evt.target.closest( ".hide-widget" );
            if ( !btn ) return;
            evt.preventDefault();
            var card = btn.closest( "[data-widget-id]" );
            if ( !card || !hideUrl ) return;
            var widgetId = card.getAttribute( "data-widget-id" );
            postForm( hideUrl, { widgetId : widgetId, hidden : true } ).then( function( res ){
                if ( res.ok ) {
                    // Soft-reload so the "Restore" dropdown picks the entry up
                    // and the layout reflows cleanly.
                    window.location.reload();
                }
            } );
        } );

        // The Restore dropdown lives OUTSIDE the dashboard root so we listen at document level.
        document.addEventListener( "click", function( evt ){
            var restoreBtn = evt.target.closest( ".restore-widget" );
            if ( restoreBtn && hideUrl ) {
                evt.preventDefault();
                var widgetId = restoreBtn.getAttribute( "data-widget-id" );
                if ( !widgetId ) return;
                postForm( hideUrl, { widgetId : widgetId, hidden : false } ).then( function( res ){
                    if ( res.ok ) window.location.reload();
                } );
                return;
            }
            var resetBtn = evt.target.closest( ".reset-dashboard" );
            if ( resetBtn && resetUrl ) {
                evt.preventDefault();
                postForm( resetUrl, {} ).then( function( res ){
                    if ( res.ok ) window.location.reload();
                } );
            }
        } );
    }

    function applyPoll( payload ){
        if ( !payload || !payload.widgets ) return;
        var root = $root();
        if ( !root ) return;
        Object.keys( payload.widgets ).forEach( function( id ){
            var card = root.querySelector( "[data-widget-id=\"" + id.replace( /"/g, "\\\"" ) + "\"]" );
            if ( !card ) return;
            var widgetData = payload.widgets[ id ];
            var registered = window.tbxDashboard.widgets[ id ];
            if ( widgetData && widgetData.error ) {
                card.classList.add( "widget-poll-error" );
                return;
            }
            card.classList.remove( "widget-poll-error" );
            if ( registered && typeof registered.update === "function" ) {
                try {
                    registered.update( widgetData, card );
                } catch ( e ) {
                    console.warn( "[agent-dashboard] update threw for", id, e );
                }
            }
        } );
    }

    function initPolling( root ){
        var url      = root.getAttribute( "data-poll-url" );
        var interval = parseInt( root.getAttribute( "data-poll-interval" ) || "30000", 10 );
        if ( !url || !( interval > 0 ) ) return;

        function tick(){
            if ( document.visibilityState === "hidden" ) return;
            fetch( url, { credentials : "same-origin", headers : { "Accept" : "application/json" } } )
                .then( function( res ){ return res.ok ? res.json() : null; } )
                .then( function( json ){ if ( json ) applyPoll( json ); } )
                .catch( function( e ){ console.warn( "[agent-dashboard] poll failed:", e ); } );
        }

        // Fire once on load so initial counts replace the server-rendered
        // values (which may be slightly stale by the time the JS runs).
        tick();
        setInterval( tick, interval );
    }

    function init(){
        var root = $root();
        if ( !root ) return;
        initSortable( root );
        initHideRestoreReset( root );
        initPolling( root );
    }

    if ( document.readyState === "loading" ) {
        document.addEventListener( "DOMContentLoaded", init );
    } else {
        init();
    }
})();
