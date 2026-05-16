/**
 * B2Provider: cbfs disk provider for Backblaze B2 (and any
 * other S3-compatible endpoint whose hostname embeds the
 * region — Wasabi, certain DigitalOcean Spaces regions, etc.).
 *
 * Identical to cbfs's stock S3Provider EXCEPT it swaps the
 * underlying s3sdk client for our PatchedAmazonS3 subclass,
 * which corrects the path-style URL builder for non-AWS
 * domains. See PatchedAmazonS3.cfc for the bug detail.
 *
 * Why a separate provider rather than always patching
 * ----------------------------------------------------
 * The patch only applies when urlStyle=path AND the awsDomain
 * is NOT an AWS domain. We could check those conditions inside
 * a single "smart" provider, but keeping `s3` (stock) and `b2`
 * (patched) as separate disks makes the operator's choice
 * explicit in the config: real AWS buckets always go through
 * cbfs's untouched S3Provider, B2 / Wasabi / generic
 * S3-compatible go through this one. No surprise behavior on
 * AWS.
 *
 * Originally written for the bx-Blogger project; ported here
 * with the same activation rule.
 *
 * @extends cbfs.models.providers.S3Provider
 */
component extends="cbfs.models.providers.S3Provider" {

	/**
	 * Run the parent's startup first so all the standard
	 * properties (accessKey, secretKey, bucket, etc.) get
	 * applied, then conditionally replace the s3 client with
	 * the patched subclass. cbfs reads `variables.s3` for every
	 * operation; the patched class is fully ABI-compatible
	 * with the parent so the swap is safe.
	 */
	public any function startup( required string name, struct properties = {} ) {
		super.startup( argumentCollection = arguments );

		var awsDomain = arguments.properties.awsDomain ?: "amazonaws.com";
		var urlStyle  = arguments.properties.urlStyle  ?: "path";

		if ( urlStyle == "path" && !( awsDomain contains "amazonaws.com" ) ) {
			try {
				variables.s3 = createObject( "component", "modules_app.core.models.cbfs.PatchedAmazonS3" )
					.init( argumentCollection = arguments.properties );
				variables.wirebox.autowire( variables.s3 );
			} catch ( any e ) {
				throw(
					type    = "tesserabx.B2Provider.ConfigurationException",
					message = "B2Provider failed to swap in PatchedAmazonS3: " & e.message
				);
			}
		}

		return this;
	}

}
