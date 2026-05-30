# channels

Responsibility, owned entities, public service interface, and events for the `channels` module.

The `channels` module handles inbound intake (email today) and normalizes each message into the
ticket model by calling `TicketsService`. It owns the inbound blacklist. It never writes contact
or ticket entities directly; it calls the owning module's service layer.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and [docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Owned entities

- **ChannelBlacklistEntry** - an email-address or domain blacklist entry, checked on every inbound
  message before a ticket is created.
- **InboundEmail** - the audit log row recorded for every processed inbound message (outcome:
  ticket_created, message_appended, duplicate, blocked_blacklist, blocked_loop_guard, error).

## Inbound email flow (`IMAPPoller` -> `InboundEmailProcessor`)

The scheduler polls IMAP every 60s and hands each message to `InboundEmailProcessor.process()`,
which runs: duplicate check -> loop guard -> blacklist -> reply matching -> new ticket.

### Sender resolution and approved-domain auto-provisioning

Both the reply-append and new-ticket paths resolve the sender through
`ContactsService.resolveOrAutoProvisionContact(sender)` rather than a plain email lookup. When the
sender's domain is an approved, verified domain on an organization that has auto-provisioning
enabled, that call creates a Contact (source `domain-auto`) in the organization and the resulting
ticket is contact-backed and tenant-scoped. Otherwise the resolver returns null and the ticket is
created accountless exactly as before. The decision lives entirely in `ContactsService`; this
module just asks.

## Public service interface (`ChannelsService`)

Blacklist: `blockEmail`, `blockDomain`, `isBlocked`, `listBlacklist`, `toggleBlacklistEntry`,
`removeBlacklistEntry`. Inbound audit: `recordInboundEmail` and lookups by outcome / sender.

## Events emitted

Inbound processing announces ticket events through `TicketsService` (e.g. `onTicketCreated`); the
channels module itself records inbound_emails audit rows and blacklist audit events.
