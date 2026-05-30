// Define the TesseraBX utility class. The class is intentionally NOT named
// "TesseraBX": a top-level `class TesseraBX {}` would create a global
// lexical binding that shadows `window.TesseraBX` for any bare reference
// (e.g. the `TesseraBX.showSuccessToast(...)` string CBWire's js() evals in
// an Alpine scope), so the name would resolve to the class, not the
// singleton instance. Naming the class differently leaves bare `TesseraBX`
// resolving to the window property, which is the public API.
class TesseraBXUtil {

	constructor() {
		// Sensible, overridable defaults. Tweak through init( {...} ).
		this.options = {
			defaultTimeout : 20000, // auto-dismiss after 20s (0 = sticky)
			containerId    : "site-toast-container",
			containerClass : "toast-container position-fixed top-0 end-0 p-3"
		};
	}

	// Init method to configure the instance. Safe to call more than once.
	init( options = {} ) {
		// Merge passed in options with defaults
		this.options = Object.assign( {}, this.options, options );
		return this;
	}

	/*
		HTML-escape a value before it is injected into toast markup. Toast
		messages routinely carry user data (contact names, ticket subjects),
		so everything is escaped by default; callers that genuinely need
		markup opt in with { allowHtml : true }.
	*/
	escapeHtml( value ) {
		if ( value === null || value === undefined ) return "";
		const div = document.createElement( "div" );
		div.textContent = String( value );
		return div.innerHTML;
	}

	/*
		Generate a unique id. crypto.randomUUID() is only available in a
		secure context (https or localhost); fall back to a random token so
		the library still works over plain http on a LAN address.
	*/
	uniqueId() {
		if ( typeof crypto !== "undefined" && typeof crypto.randomUUID === "function" ) {
			return "toast_" + crypto.randomUUID();
		}
		return "toast_" + Math.random().toString( 36 ).slice( 2 ) + Date.now().toString( 36 );
	}

	/*
		* Show an AdminLTE toast message
		https://adminlte.io/themes/v4/UI/general.html

		The final argument may be an options object, e.g.
		showToast( "success", "Saved", "Success", "", 5000, { allowHtml : true } ).
	*/
	showToast( type, message, title = "Success", icon = "", timeout, options = {} ) {
		// Default the timeout when the caller did not pass one.
		if ( timeout === undefined || timeout === null ) {
			timeout = this.options.defaultTimeout;
		}
		const allowHtml = options.allowHtml === true;
		// grab the container element for the toasts
		let container = document.querySelector( "#" + this.options.containerId );
		if ( !container ) {
			// if it doesn't exist, create it and append to the body
			container = document.createElement( "div" );
			container.className = this.options.containerClass;
			container.id = this.options.containerId;
			document.body.appendChild( container );
		}
		// generate a unique ID
		const id = this.uniqueId();
		// Human-readable timestamp (12hr format)
		const now = new Date();
		const timestamp = now.toLocaleTimeString( "en-US", { hour: "numeric", minute: "2-digit" } );
		// set colors and icon based on type
		let toastTypeClass = "";
		let toastTypeIcon = "";
		switch ( type ) {
			case "success":
				toastTypeClass = "toast-success";
				toastTypeIcon = icon.length ? icon : "bi bi-check-circle-fill";
				break;
			case "info":
				toastTypeClass = "toast-info";
				toastTypeIcon = icon.length ? icon : "bi bi-info-circle-fill";
				break;
			case "warning":
				toastTypeClass = "toast-warning";
				toastTypeIcon = icon.length ? icon : "bi bi-exclamation-circle-fill";
				break;
			case "primary":
				toastTypeClass = "toast-primary";
				toastTypeIcon = icon.length ? icon : "bi bi-bell-fill";
				break;
			case "secondary":
				toastTypeClass = "toast-secondary";
				toastTypeIcon = icon.length ? icon : "bi bi-bell-fill";
				break;
			case "light":
				toastTypeClass = "toast-light";
				toastTypeIcon = icon.length ? icon : "bi bi-bell-fill";
				break;
			case "dark":
				toastTypeClass = "toast-dark";
				toastTypeIcon = icon.length ? icon : "bi bi-bell-fill";
				break;
			case "danger":
			case "error": // danger and error will use the same styling
				toastTypeClass = "toast-danger";
				toastTypeIcon = icon.length ? icon : "bi bi-sign-stop-fill";
				break;
			default:
				toastTypeClass = "toast-light";
				toastTypeIcon = icon.length ? icon : "bi bi-bell-fill";
		}
		// Escape unless the caller explicitly opted into markup. The icon
		// class is library-controlled, so it is never escaped.
		const safeTitle = allowHtml ? ( title || "" ) : this.escapeHtml( title );
		const safeMessage = allowHtml ? message : this.escapeHtml( message );
		// Build toast HTML
		const toastHtml = `
		<div id="${id}" class="toast  ${toastTypeClass} mb-1" role="alert" aria-live="assertive" aria-atomic="true">
			<div class="toast-header">
			<strong class="me-auto"><i class="${toastTypeIcon}"></i> ${safeTitle}</strong>
			<small class="text-muted">${timestamp}</small>
			<button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
			</div>
			<div class="toast-body">${safeMessage}</div>
		</div>`;
		// Insert toast into the container
		container.insertAdjacentHTML( "beforeend", toastHtml );
		// Init + show the toast using AdminLTE's Toast class
		const el = document.getElementById( id );
		const toast = new bootstrap.Toast( el, {
			autohide: timeout > 0,
			delay: timeout
		} );
		toast.show();
		// Cleanup after hidden
		el.addEventListener( "hidden.bs.toast", () => el.remove() );
		// return the id of the toast for reference if needed
		return id;
	}
	/* Toast helper functions */
	showSuccessToast( message, title = "Success", icon = "", timeout, options = {} ) {
		return this.showToast( "success", message, title, icon, timeout, options );
	}
	showInfoToast( message, title = "Info", icon = "", timeout, options = {} ) {
		return this.showToast( "info", message, title, icon, timeout, options );
	}
	showWarningToast( message, title = "Warning", icon = "", timeout, options = {} ) {
		return this.showToast( "warning", message, title, icon, timeout, options );
	}
	showPrimaryToast( message, title = "Notice", icon = "", timeout, options = {} ) {
		return this.showToast( "primary", message, title, icon, timeout, options );
	}
	showSecondaryToast( message, title = "Notice", icon = "", timeout, options = {} ) {
		return this.showToast( "secondary", message, title, icon, timeout, options );
	}
	showLightToast( message, title = "Notice", icon = "", timeout, options = {} ) {
		return this.showToast( "light", message, title, icon, timeout, options );
	}
	showDarkToast( message, title = "Notice", icon = "", timeout, options = {} ) {
		return this.showToast( "dark", message, title, icon, timeout, options );
	}
	// Error/danger toasts are sticky by default (timeout 0) so a failure is
	// not missed; pass an explicit timeout to override.
	showDangerToast( message, title = "Error", icon = "", timeout = 0, options = {} ) {
		return this.showToast( "error", message, title, icon, timeout, options );
	}
	showErrorToast( message, title = "Error", icon = "", timeout = 0, options = {} ) {
		return this.showToast( "error", message, title, icon, timeout, options );
	}

	/*
		Initialize Bootstrap tooltips within a root element, skipping any
		element that is already initialized. Safe to call repeatedly, which
		is what lets us re-run it after CBWire morphs new DOM into the page.
	*/
	initTooltips( root = document ) {
		if ( typeof bootstrap === "undefined" || !bootstrap.Tooltip ) return;
		const triggers = root.querySelectorAll( '[data-bs-toggle="tooltip"]' );
		triggers.forEach( ( el ) => {
			if ( !bootstrap.Tooltip.getInstance( el ) ) {
				new bootstrap.Tooltip( el );
			}
		} );
	}
} // End TesseraBXUtil class

/*
	Construct the singleton SYNCHRONOUSLY at parse time and expose it as the
	global window.TesseraBX. The toast methods only touch the DOM when called,
	so they are safe before DOMContentLoaded, and this guarantees
	window.TesseraBX exists for any flash / CBWire js() script that runs
	earlier in the document than this file. Bare `TesseraBX` references
	resolve to this window property (the class is named TesseraBXUtil so it
	does not shadow it).
*/
window.TesseraBX = new TesseraBXUtil();
window.TesseraBX.init();

/* DOM-dependent site-wide initialization (tooltips). */
( function () {
	function bootstrapInit() {
		window.TesseraBX.initTooltips( document );
	}
	if ( document.readyState !== "loading" ) {
		bootstrapInit();
	} else {
		document.addEventListener( "DOMContentLoaded", bootstrapInit );
	}

	// Re-initialize tooltips inside DOM that CBWire/Livewire morphs in.
	document.addEventListener( "livewire:init", function () {
		if ( typeof Livewire === "undefined" ) return;
		Livewire.hook( "morphed", ( { el } ) => {
			window.TesseraBX.initTooltips( el || document );
		} );
	} );
} )();
