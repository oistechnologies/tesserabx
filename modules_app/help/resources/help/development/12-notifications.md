## Notification templates

The notifications module ships two registries: `NotificationTemplateRegistry@notifications` for the per-event message templates and `NotificationChannelRegistry@notifications` for the delivery channels (in-app, email, slack, plus add-on channels).

Templates are keyed on the tuple `(event_key, channel, recipient_type)`. The `notification_templates` DB table is the **overrides** layer; the registry is the **defaults** layer. When `NotificationsService.dispatchForEvent` resolves the template set for an event, it overlays the DB rows on top of the registry seeds, so an admin-edited template wins, and a tuple that has no DB row still delivers (the registry default takes over).

### Declaring a template

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.notificationTemplates = [
    {
        eventKey      : "exampleJira.issue_linked",
        channel       : "email",
        recipientType : "agent",
        titleTemplate : "Jira issue {{issueKey}} linked to ticket {{ticketNumber}}",
        bodyTemplate  : "{{authorLabel}} linked {{issueKey}} to ticket {{ticketNumber}}.",
        linkTemplate  : "{{appBaseUrl}}/agent/tickets/{{ticketId}}",
        placeholders  : [ "issueKey", "ticketNumber", "ticketId", "authorLabel" ]
    }
];
```

| Field           | Required    | Notes                                                                          |
| --------------- | ----------- | ------------------------------------------------------------------------------ |
| `eventKey`      | yes         | Must match the event key your interceptor or service announces.                |
| `channel`       | yes         | Must be a registered channel id (see below).                                   |
| `recipientType` | yes         | `agent` or `contact`.                                                          |
| `titleTemplate` | yes         | Notification title / email subject / slack header.                             |
| `bodyTemplate`  | yes         | Notification body / email body / slack body.                                   |
| `linkTemplate`  | recommended | Deep link; empty string when not applicable.                                   |
| `placeholders`  | optional    | Array of token names the template references. Documentation only at runtime.  |

`{{appBaseUrl}}` and `{{unsubscribeUrl}}` are injected by the dispatcher and available in every template.

### Public extension contract

```
var registry = wirebox.getInstance( "NotificationTemplateRegistry@notifications" );
var all      = registry.listAll();
var byEvent  = registry.listForEvent( "ticket.created" );
var single   = registry.findTemplate( "ticket.created", "inapp", "agent" );
```

## Notification channels

Three channels ship out of the box: `inapp` (the bell dropdown), `email` (cbmailservices + admin-managed mail override), and `slack` (Slack/Teams incoming webhook via the `SLACK_WEBHOOK_URL` setting). Each is a thin class that conforms to the `INotificationChannel` contract.

### The contract

`INotificationChannel` is documented inline at `modules_app/notifications/models/contracts/INotificationChannel.bx`. The four methods:

| Method                | Returns | Purpose                                                                                                 |
| --------------------- | ------- | ------------------------------------------------------------------------------------------------------- |
| `getChannelId()`      | string  | Stable id (e.g. `email`). Matches the `channel` field on template rows.                                 |
| `getDisplayName()`    | string  | Human label for the admin UI and per-user preferences page.                                             |
| `send( notification )`| void    | Deliver one persisted Notification. Mutate `status` to `sent` or `failed`, save before returning.       |
| `supportsBatch()`     | boolean | Reserved. Return false; the dispatcher today calls `send()` once per recipient.                         |

Implementations are WireBox singletons so per-channel state (HTTP client, cached settings) stays scoped to the channel class.

### Declaring an add-on channel

In your add-on's `ModuleConfig.bx`:

```
settings.tesserabx.notificationChannels = [
    {
        id          : "sms",
        displayName : "SMS",
        wirebox     : "TwilioSmsChannel@addon-twilio"
    }
];
```

`wirebox` is the WireBox alias of your channel implementation. The channel registry resolves the alias when dispatching.

| Field         | Required | Notes                                                                |
| ------------- | -------- | -------------------------------------------------------------------- |
| `id`          | yes      | Stable channel id; must match what your templates declare as `channel`. |
| `displayName` | yes      | Label rendered in the per-user preferences UI.                        |
| `wirebox`     | yes      | WireBox alias of the implementation class.                            |

Once the channel is registered, write a template for it via `settings.tesserabx.notificationTemplates`, and any event whose dispatched recipients have an enabled preference on that channel will be delivered through your `send()`.

### What the dispatcher does

For each `(recipient, channel)` pair:

1. Look up the template (DB overrides over registry defaults).
2. Skip if the channel id is not registered.
3. Skip if the recipient has set `notification_preferences.enabled = false` for that `(event, channel)`.
4. Build the per-recipient context (`{{appBaseUrl}}`, `{{unsubscribeUrl}}`), render title / body / link.
5. Persist a `Notification` row in status `pending` (or `sent` for `inapp`).
6. Hand off to `channelRegistry.send( channelId, notification )`, which resolves your implementation and calls its `send()`.

The dispatcher tolerates unknown channels and missing templates without throwing; either condition silently skips that fan-out leg.

### Public extension contract

```
var registry = wirebox.getInstance( "NotificationChannelRegistry@notifications" );
var all      = registry.listAll();
var ok       = registry.isRegistered( "email" );
var impl     = registry.resolve( "email" );           // returns the channel class
registry.send( "email", notification );               // deliver one row
```

---

