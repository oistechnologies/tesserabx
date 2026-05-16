/**
 * PatchedAmazonS3: subclass of s3sdk's AmazonS3 that fixes the
 * path-style URL builder for non-AWS S3-compatible endpoints
 * whose hostname already embeds the region (e.g. Backblaze B2,
 * Wasabi, DigitalOcean Spaces in some regions).
 *
 * Bug being patched
 * -----------------
 * `s3sdk.models.AmazonS3.buildUrlEndpoint( bucketName )` always
 * prepends `awsRegion` to `awsDomain` when `urlStyle == "path"`,
 * regardless of whether the domain is AWS. For Backblaze B2 with
 *     awsDomain = "s3.us-west-004.backblazeb2.com"
 *     awsRegion = "us-west-004"
 * the result is
 *     "us-west-004.s3.us-west-004.backblazeb2.com"
 * which B2 rejects with 403 AccessDenied.
 *
 * Why a subclass works where on-instance overrides don't
 * --------------------------------------------------------
 * AmazonS3 calls `buildUrlEndpoint( bucketName )` internally from
 * putObject / getObject / a handful of other entry points as
 * unqualified calls (no `this.` prefix). Those resolve through
 * the component's `variables` scope, so an on-instance closure
 * override never fires. Subclass virtual dispatch DOES pick up
 * the override uniformly, so this subclass intercepts every
 * internal call site.
 *
 * The override is scoped: only path-style URLs against a non-AWS
 * domain are patched. AWS proper and virtual-style URLs defer
 * to the parent (those code paths aren't broken).
 *
 * NOTE: .cfc rather than .bx because s3sdk's AmazonS3 is itself
 * a .cfc and BoxLang's bx/cfc inheritance model needs the child
 * to use the same `component` keyword the parent uses.
 *
 * Originally written for the bx-Blogger project; ported here
 * unchanged so the same proven fix carries forward.
 *
 * @extends s3sdk.models.AmazonS3
 */
component extends="s3sdk.models.AmazonS3" {

	public any function buildUrlEndpoint( string bucketName ) {
		var awsDomain = variables.awsDomain    ?: "";
		var isAws     = awsDomain contains "amazonaws.com";
		var isPath    = ( variables.urlStyle ?: "" ) == "path";

		if ( isPath && !isAws ) {
			var protocol                  = ( variables.ssl ) ? "https://" : "http://";
			variables.URLEndpointHostname = awsDomain;
			variables.URLEndpoint         = protocol & awsDomain;
			return this;
		}

		// AWS or virtual-style — let the original method run.
		return super.buildUrlEndpoint( argumentCollection = arguments );
	}

}
