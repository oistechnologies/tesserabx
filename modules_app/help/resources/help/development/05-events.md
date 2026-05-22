## Events

Every state transition core cares about announces an interceptor event other modules and add-ons can listen on. Add-ons hook into these events by declaring an interceptor in their `ModuleConfig.bx` with a method named after the event, then doing whatever work the add-on needs.

```boxlang
// modules/example-jira/interceptors/JiraSyncInterceptor.bx
class {
    property name="wirebox" inject="wirebox";

    function configure(){}

    function onTicketStatusChanged( event, interceptData, rc, prc ){
        // interceptData carries the payload struct emitted by the
        // event source. See the canonical payload shape below.
    }
}
```

Then register the interceptor in `ModuleConfig.bx`:

```boxlang
variables.interceptors = [
    {
        class      : "#moduleMapping#.interceptors.JiraSyncInterceptor",
        name       : "JiraSyncInterceptor",
        properties : {}
    }
];
```

### Canonical event payload

Every event TesseraBX announces from Phase 3 onwards uses the same envelope (produced by `EventPayloadBuilder@core`):

```
{
    event          : "onContactCreated",
    occurredAt     : "<ISO-8601 UTC>",
    organizationId : "<uuid>" or "",
    actorType      : "agent" | "contact" | "system",
    actorId        : "<uuid>" or "system",
    entity         : { type: "Contact", id: "<uuid>" },
    before         : <struct or null>,
    after          : <struct or null>,
    metadata       : <struct>
}
```

The five pre-Phase-3 events keep their original payload shapes for backwards compatibility with the existing core interceptors that consume them:

- `onTicketCreated`: `{ ticket : <Ticket entity>, accountless : boolean }`
- `onTicketMessageAdded`: `{ message : <TicketMessage entity>, ticket : <Ticket entity> }`
- `onTicketStatusChanged`: `{ ticket : <Ticket entity>, statusChange : { from : "...", to : "..." } }`
- `onKbArticlePublished`: `{ article : <Article entity> }`

New listeners for these events get the existing entity-shaped struct, not the canonical envelope.

### Async vs sync policy

By default, **new events use `announceAsync`**: they cannot stall the request that triggered them. Add-on listeners therefore run after the originating response is committed, in a separate thread.

A handful of events stay **synchronous** because they need to influence the in-flight transaction (automation rules that mutate the same ticket the user just edited, AI triage that writes summary fields before the response renders). The five pre-Phase-3 events are sync for this reason.

When listening on an async event, do not assume the originating database row is still in its post-write state. Read the entity by id if you need the latest values.

### Event catalog (Phase 3)

Events fire from these core modules. The list grows as later phases (channels, SLA, automation, KB-beyond-publish, AI, API webhooks) ship their own events.

**tickets** (declared in `modules_app/tickets/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onTicketCreated` | sync | A ticket is created (with or without a Contact). |
| `onTicketMessageAdded` | sync | A reply or internal note is added. |
| `onTicketStatusChanged` | sync | A status transition occurs. |
| `onTicketAssigned` | async | Assignment changes (including unassignment). |
| `onTicketTagsAdded` | async | One or more tags are added. |
| `onTicketAttachmentAdded` | async | A file is attached. |
| `onTicketAttachmentDeleted` | async | An attachment is soft-deleted. |
| `onTicketPromotedToContact` | async | An accountless ticket's sender is promoted to a real Contact. |

**contacts** (declared in `modules_app/contacts/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onOrganizationCreated` | async | A new organization is created. |
| `onContactProvisioned` | async | A new Contact account is provisioned. |
| `onContactDeactivated` | async | A Contact is deactivated. |
| `onContactRoleGranted` | async | A role is assigned to a Contact. |
| `onContactRoleRevoked` | async | A role is revoked from a Contact. |
| `onOrganizationDomainMapped` | async | A domain is mapped to an organization. |
| `onContactMerged` | async | Two Contacts are merged. |

**agent + RBAC** (declared in `modules_app/agent/ModuleConfig.bx`):

| Event | Sync? | Fires when |
| --- | --- | --- |
| `onAgentCreated` | async | A new agent account is created. |
| `onAgentUpdated` | async | An agent profile is updated (and `isActive` did NOT flip). |
| `onAgentActivated` | async | An agent is activated (isActive flips false → true). |
| `onAgentDeactivated` | async | An agent is deactivated (isActive flips true → false). |
| `onAgentRoleGranted` | async | A role is granted to an agent. |
| `onAgentRoleRevoked` | async | A role is revoked from an agent. |

**knowledgebase**: only `onKbArticlePublished` (sync) ships in Phase 3. Other lifecycle events for articles are planned for a later phase.

---

## Audit-event contributions

Add-ons can write to the central audit log alongside core. Use `AuditService@audit`:

```boxlang
property name="auditService" inject="AuditService@audit";

auditService.record(
    eventType      : "exampleJira.issueCreated",
    entityType     : "Ticket",
    entityId       : ticketId,
    organizationId : orgId,
    actorType      : "agent",
    actorId        : currentAgentId,
    metadata       : { jiraIssueKey : "PROJ-123", projectKey : "PROJ" },
    source         : "example-jira"
);
```

The `source` argument is the add-on's `addonId`. Core events leave it null. The admin audit search UI exposes a Source filter dropdown so an operator can see exactly what each add-on has done, independently of core noise.

### Declaring your audit event types in the manifest

So that an add-on's event types appear in the admin search dropdown **before** they have ever fired, declare them in the manifest:

```boxlang
settings = {
    tesserabx : {
        addonId : "example-jira",
        // ... other manifest fields
        auditEvents : [
            { type : "exampleJira.issueCreated", label : "Jira issue created", severity : "info" },
            { type : "exampleJira.issueClosed",  label : "Jira issue closed",  severity : "info" }
        ]
    }
};
```

`AuditService.listEventTypes()` merges the distinct types already in the log with every add-on's declared types, deduplicates, and returns a sorted array. The dropdown surfaces a type the moment the add-on is discovered, not the first time an event of that type happens.

### Audit-event naming convention

Use dotted notation with the add-on slug as the prefix: `<addonId>.<verb_noun>`. Examples: `example-jira.issue_created`, `example-jira.issue_closed`, `billing.invoice_sent`. Core uses the same convention with an entity prefix (`ticket.created`, `contact.merged`, etc.).

---

