## Email templates

A notification template is enough to deliver a fully working branded email. The core `MailComposerService@core` reads each notification's plain-text `bodyTemplate`, auto-renders it to HTML (paragraphs, links), wraps it in the configured brand chrome, and ships both an HTML and a plain-text part. Your add-on does not have to know any of that.

For the cases where the auto-render is not enough, an add-on can ship its own body view as a `.bxm` partial and point at it through an *email template* entry. The composer renders that partial as the inner body and keeps the surrounding chrome from the core layout.

Use email templates when:

- You want a structured layout (data table, metadata card, call-to-action button) the auto-render cannot produce from plain text.
- You want to embed brand-specific imagery the chrome does not already pull in.
- You want different copy at different breakpoints by adding inline `@media` rules inside your partial.

### What an email template is

An email template is a `{ id, displayName, subject, module, partial, placeholders }` entry declared in `settings.tesserabx.emailTemplates`. The `module` and `partial` together resolve to a ColdBox view (a `.bxm` file under your add-on's `views/`) that the composer renders as the inner body of the email. The partial receives a fixed set of variables in `args` (see *Where the partial lives* below).

This is **distinct from a notification template**: a notification template is the event-driven message body that the dispatcher resolves automatically when an event fires; an email template is an opt-in body view your add-on can name and have the composer render, typically from a dedicated send path.

### Declaring an email template

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.emailTemplates = [
    {
        id           : "issueLinkedDigest",
        displayName  : "Issue-linked digest",
        subject      : "Daily digest: {{linkedCount}} ticket links",
        module       : "example-sync",
        partial      : "emails/issue_linked_digest",
        placeholders : [ "linkedCount", "appBaseUrl", "productName" ],
        requiresAi   : false
    }
];
```

| Field          | Required | Notes                                                                                                                  |
| -------------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| `id`           | yes      | Stable per-add-on identifier. Surfaces in the admin email-preview screen's template picker.                            |
| `displayName`  | yes      | Human label for the same picker.                                                                                       |
| `subject`      | yes      | Default subject line. May contain `{{token}}` placeholders the calling code substitutes before invoking the composer.  |
| `module`       | yes      | Your module name. The composer uses this when resolving the partial.                                                   |
| `partial`      | yes      | View path relative to your module's `views/` folder, without the `.bxm` suffix.                                        |
| `placeholders` | optional | Array of token names the partial references. Documentation only at runtime; the composer does not validate against it. |
| `requiresAi`   | optional | When `true`, the four UI registries hide this entry while `AI_ENABLED=false`. Default `false`.                          |

### Where the partial lives

The partial is a regular `.bxm` view inside your add-on, for example `views/emails/issue_linked_digest.bxm`. The composer renders it through `controller.getRenderer().renderView(...)` with these `args` in scope:

| Variable       | Type    | Notes                                                                          |
| -------------- | ------- | ------------------------------------------------------------------------------ |
| `brand`        | struct  | Resolved branding (`productName`, `tagline`, `logoUrl`, `primaryColor`, `footerText`). Per-org overrides already merged. |
| `tokens`       | struct  | The `tokens` argument the caller passed to `compose()`.                        |
| `appBaseUrl`   | string  | Absolute URL prefix. Use to build links inside the body.                       |
| `logoTarget`   | string  | Resolved absolute logo URL (configured value, or bundled default).             |
| `primaryColor` | string  | Normalized hex color, ready to inline as a `style="background:..."` value.     |
| `style`        | string  | `notification` or `reply`. Useful for partials that subtly adapt to either.    |
| `eventKey`     | string  | The `eventKey` argument; useful when one partial serves several events.        |
| `preheader`    | string  | Inbox-preview text. The wrapping layout renders this; partials can ignore it.  |

Constraint reminders for the partial:

- **Inline CSS only.** Email clients strip `<style>` blocks. The wrapping chrome controls fonts and the overall column width; your partial controls the inside.
- **Table-based layout** for any multi-column structure. Email clients flake on flexbox and grid.
- **No em dashes** anywhere in the partial (per the project's deliverable rule). Use commas, parentheses, or restructured sentences.

### Resolution and overrides

`EmailTemplateRegistry@core` reads `settings.tesserabx.emailTemplates` from every loaded module at boot and exposes:

```
var registry = wirebox.getInstance( "EmailTemplateRegistry@core" );
var all      = registry.listAll();                  // every registered template
var single   = registry.findById( "issueLinkedDigest" );
```

The admin email-preview screen at `/agent/admin/email-preview` lists registered templates in the picker. v1 ships the registry as read-only; admin DB-side overrides are a follow-up.

### Public extension contract

What is stable for add-on authors:

- The shape of an `emailTemplates` array entry (the seven fields above).
- The `args` struct variables a body partial can rely on.
- `EmailTemplateRegistry@core.listAll()` and `findById( id )`.
- The wrapping chrome contract: your partial controls the inside; the composer wraps it in the layout selected by `style`.

What is not stable yet, and may change:

- The `placeholders` field. Today it is documentation; future versions may use it to validate that every declared token resolves to a non-empty value before send.
- The pool of in-scope variables in the partial. New ones may appear; existing ones will not be renamed without a deprecation cycle.

## Sending email from an add-on

Every outbound email in TesseraBX goes through the single `MailComposerService@core`. Add-ons inject it the same way as any other service and call `compose()` to produce a Mail object, then `send()` to ship it.

The composer takes care of: branding resolution (global vs per-organization), the HTML chrome, the plain-text alternative, the documented ops headers (`X-TesseraBX-Event`, `X-TesseraBX-Organization`), and the admin-managed SMTP override. Add-ons supply the recipient, subject, and body; everything else has a sensible default.

### The MailComposerService API

```
class {

    property name="mailComposer" inject="MailComposerService@core";

    function welcome( required any contact ){
        var mail = mailComposer.compose(
            to             : contact.getEmail(),
            subject        : "Welcome to support, {{name}}!",
            body           : "Hi {{name}},\n\nThanks for getting in touch. We are glad you are here.\n\nThe team",
            bodyFormat     : "text",
            recipientType  : "contact",
            organizationId : contact.getOrganizationId(),
            eventKey       : "myaddon.contact.welcome",
            tokens         : { name : contact.getFirstName() }
        );
        mailComposer.send( mail );
    }

}
```

`compose()` arguments worth knowing:

| Argument             | Default                  | Notes                                                                                                                |
| -------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `to`                 | required                 | Recipient address.                                                                                                   |
| `subject`            | required                 | Subject line. May contain unsubstituted `{{tokens}}`; substitute through `tokens` before the call.                   |
| `from`               | env `MAIL_FROM`          | Bare address. The composer wraps it with the `email.from_name` setting (or `brand.product_name`) as a friendly label. |
| `replyTo`            | `email.reply_to` setting | Reply-To header.                                                                                                     |
| `body`               | empty                    | Raw HTML (default) or plain text when `bodyFormat = "text"`.                                                         |
| `bodyFormat`         | `"html"`                 | Set to `"text"` to have the composer paragraphize on `\n\n`, auto-link URLs, and HTML-escape special chars.          |
| `bodyTemplate`       | `{}`                     | `{ module, partial }` reference to an add-on body partial (an email template entry).                                 |
| `layoutTemplate`     | `{}`                     | `{ module, partial }` to replace the wrapping chrome entirely. Rare; most add-ons leave this empty.                  |
| `style`              | `"notification"`         | `"notification"` (full chrome) or `"reply"` (thin chrome, person-to-person feel).                                    |
| `recipientType`      | `"raw"`                  | `"agent"`, `"contact"`, or `"raw"`. Drives the brand-resolution rule below.                                          |
| `organizationId`     | `""`                     | Tenant context. Required for per-organization branding to kick in.                                                   |
| `preheader`          | `email.preheader_default`| Inbox-preview text. Hidden in the rendered body, surfaces in the inbox list.                                         |
| `eventKey`           | `""`                     | Populates the `X-TesseraBX-Event` header.                                                                            |
| `listUnsubscribeUrl` | `""`                     | When non-blank and `style = "notification"`, emits the `List-Unsubscribe` and `List-Unsubscribe-Post` headers.        |
| `tokens`             | `{}`                     | Substitution data passed to a body partial; ignored when no `bodyTemplate` is set.                                   |
| `headers`            | `{}`                     | Arbitrary extra headers. Use for `Message-ID`, `In-Reply-To`, `References` when threading a ticket reply.            |
| `attachments`        | `[]`                     | Reserved for future use. Add attachments by mutating the returned Mail object directly until this lands.             |

### Composing without a custom template

If your add-on needs to send a one-off message and the auto-render is enough, skip `bodyTemplate` entirely and pass the body as either raw HTML or plain text:

```
// Plain-text body, auto-rendered to HTML
var mail = mailComposer.compose(
    to         : "user@example.com",
    subject    : "Welcome",
    body       : "Hi,\n\nWelcome aboard.\n\nThe team",
    bodyFormat : "text"
);
mailComposer.send( mail );

// Pre-rendered HTML body (caller built it)
var mail = mailComposer.compose(
    to         : "user@example.com",
    subject    : "Statement ready",
    body       : "<p>Your statement is ready.</p><p><a href=""...."">Download PDF</a></p>"
);
mailComposer.send( mail );
```

### Composing with a custom template

Declare the template in your manifest (see *Email templates* above), then point the composer at it through `bodyTemplate`:

```
var mail = mailComposer.compose(
    to             : agent.getEmail(),
    subject        : "Daily digest: " & linkedCount & " ticket links",
    bodyTemplate   : { module : "example-sync", partial : "emails/issue_linked_digest" },
    tokens         : {
        linkedCount : linkedCount,
        links       : recentLinks
    },
    recipientType  : "agent",
    eventKey       : "exampleSync.digest"
);
mailComposer.send( mail );
```

Inside `views/emails/issue_linked_digest.bxm`:

```
<bx:output>
<p style="margin:0 0 16px 0;">
    You linked <strong>#args.tokens.linkedCount#</strong> ticket(s) to external issues today.
</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border-collapse:collapse;">
    <bx:loop array="#args.tokens.links#" item="row">
        <tr>
            <td style="padding:8px 0;border-bottom:1px solid ##eee;">
                #encodeForHTML( row.issueKey )# -> #encodeForHTML( row.ticketSubject )#
            </td>
        </tr>
    </bx:loop>
</table>
<p style="margin:16px 0 0 0;">
    <a href="#encodeForHTMLAttribute( args.appBaseUrl & '/agent/reports/issue-links' )#"
       style="background:#args.primaryColor#;color:##ffffff;text-decoration:none;padding:10px 16px;display:inline-block;border-radius:4px;">View report</a>
</p>
</bx:output>
```

### Brand context and recipient type

The composer resolves which brand to render with based on `recipientType` and `organizationId`:

| `recipientType` | `organizationId` | Brand source                                                                            |
| --------------- | ---------------- | --------------------------------------------------------------------------------------- |
| `agent`         | any              | Global (provider) brand. Agents see across organizations; the global brand is correct.  |
| `contact`       | empty            | Global brand. Unscoped recipient.                                                       |
| `contact`       | a tenant id      | Per-org brand merged over global. Per-org non-blank columns win; blanks fall through.   |
| `raw`           | empty            | Global brand. Unknown sender (accountless ticket, password-reset to a stranger).        |

You only need to set `organizationId` when sending to a `contact` and want their organization's branding overrides to apply. Setting it for an `agent` recipient is harmless; the composer will still pick the global brand.

### Headers and deliverability

Every email the composer produces carries these headers:

- `X-TesseraBX-Event` (when `eventKey` is non-blank): mirrors the event that triggered the send. Useful for filtering in the inbound matcher and for ops debugging.
- `X-TesseraBX-Organization` (always): the tenant id, or `unknown` when there is no tenant context.
- `From: "Friendly Name" <bare-address>`: friendly name resolved from `email.from_name` setting, then `brand.product_name`.

When you set `listUnsubscribeUrl` and `style = "notification"`, the composer additionally emits the RFC 8058 one-click unsubscribe headers:

- `List-Unsubscribe: <url>, <mailto:from?subject=unsubscribe>`
- `List-Unsubscribe-Post: List-Unsubscribe=One-Click`

Gmail and Outlook honor these for the native inbox unsubscribe button.

For threaded reply mail, pass `Message-ID`, `In-Reply-To`, and `References` through `headers`:

```
var mail = mailComposer.compose(
    to       : contact.getEmail(),
    subject  : "[Ticket ##" & ticket.getNumber() & "] Re: " & ticket.getSubject(),
    body     : reply,
    style    : "reply",
    eventKey : "tickets.agent_reply",
    headers  : {
        "Message-ID"  : ourGeneratedMessageId,
        "In-Reply-To" : ticket.getLatestInboundMessageId(),
        "References"  : ticket.getThreadReferencesHeader()
    }
);
```

### Sending vs queueing

`MailComposerService.send( mail )` is synchronous today. Call it directly when you want immediate delivery (and immediate error visibility). A future release will add a `composeAndQueue( ... )` path backed by cbq; switching to it will be a one-method swap on your call site, so call `composer.send( ... )` rather than reaching into cbmailservices directly.

### Public extension contract

What is stable for add-on authors:

- `MailComposerService@core` is the only documented send path for add-on mail.
- The `compose()` argument names listed above. Defaults may change; new optional arguments may appear.
- The `send()` wrapper.
- The two ops headers (`X-TesseraBX-Event`, `X-TesseraBX-Organization`).
- The `List-Unsubscribe` opt-in via `listUnsubscribeUrl`.

What is not stable yet:

- The `attachments` argument. Reserved; mutate the returned Mail object directly until it lands.
- The exact format of the friendly From label. The current `"Name" <addr>` shape works in every modern client; we may add an RFC 5322 encoder pass if non-ASCII names need it.
- Multipart shape. v1 emits `multipart/mixed` because bx-mail hardcodes that subtype; a future upstream fix or custom protocol will flip the outer to `multipart/alternative`. Both bodies are present and modern clients render correctly in either case.
