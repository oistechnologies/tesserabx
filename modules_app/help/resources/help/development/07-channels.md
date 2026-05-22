## Channel adapters

A channel adapter is an add-on contribution that lets tickets arrive from, and replies leave through, a transport core does not ship (Slack DM, SMS, Discord, an in-house webhook, etc.). The email transport ships as a core channel adapter so the registry is exercised by core itself.

### Implementing an adapter

Implement the method shape documented in `modules_app/channels/models/contracts/IChannelAdapter.bx`. Do NOT extend the contract class; just match its public surface. Every adapter must implement:

| Method                                          | Purpose                                                                                    |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `getChannelId()` → string                       | Stable identifier, lowercase, no spaces (e.g., `"email"`, `"slack-dm"`).                   |
| `getDisplayName()` → string                     | Human label for the admin Channels page.                                                   |
| `getIcon()` → string                            | Bootstrap-icon class for the admin list. May return `""`.                                  |
| `isPullBased()` → boolean                       | `true` if the host scheduler invokes `pollOnce()`; `false` for push (webhook) adapters.    |
| `verifyConfig( config )` → struct               | Admin Channels UI calls this when an operator wants to confirm a credential change.        |
| `pollOnce()` → numeric                          | Pull-based only: fetch any waiting messages and process them. Return the count handled.    |
| `normalizeInbound( raw )` → struct              | Convert one source-shaped payload into the host-normalized inbound struct (shape below).   |
| `sendOutbound( ticketMessage, ticket )` → struct | Dispatch a TicketMessage out through the channel. Returns `{ ok, error, channelMessageId }`. |

### Registering an adapter

Two paths:

**Manifest (the add-on path):**

```boxlang
// modules/my-addon/ModuleConfig.bx
settings.tesserabx.channelAdapters = [
    { mapping : "MyChannelAdapter@my-addon" }
];
```

Then map the implementation in `onLoad()` so WireBox can resolve it:

```boxlang
binder.map( "MyChannelAdapter@my-addon" )
      .to( "#moduleMapping#.models.MyChannelAdapter" )
      .asSingleton();
```

`ChannelAdapterRegistry@channels` walks every loaded module's manifest at boot, resolves each mapping, queries it for channel id / display name / icon, and caches the (id → mapping) lookup. After that, callers resolve adapters by channel id:

```boxlang
var registry = wirebox.getInstance( "ChannelAdapterRegistry@channels" );
var adapter  = registry.adapterFor( "my-channel" );
var result   = adapter.sendOutbound( ticketMessage, ticket );
```

**Imperative (the core path):**

Core's email channel adapter does NOT declare itself in a manifest because that would make `channels` appear as a distinct add-on in the admin Add-ons page. Instead, core registers imperatively in its `onLoad()`:

```boxlang
controller.getWireBox()
          .getInstance( "ChannelAdapterRegistry@channels" )
          .register( "EmailChannelAdapter@channels" );
```

Either path arrives at the same in-memory cache. Add-ons should prefer the manifest path so the admin UI surfaces the add-on as a self-contained installable artifact.

### Inbound normalized struct contract

`normalizeInbound( rawPayload )` MUST return a struct with every documented key populated. Fields whose source has no equivalent stay as empty strings, empty structs, or empty arrays. NEVER omit a key:

```
{
    messageId         : string,     // stable id from the source
    channelId         : string,     // the adapter's getChannelId()
    from              : string,     // sender display (free-form)
    senderEmail       : string,     // canonicalized email or ""
    senderHandle      : string,     // platform-specific id, or ""
    subject           : string,     // short title (may be derived from body)
    body              : string,     // plain-text body (HTML stripped)
    inReplyTo         : string,     // upstream id of the parent message, or ""
    references        : string,     // space-separated parent chain, or ""
    loopGuardHeaders  : struct,     // headers/markers identifying auto-responders
    attachments       : array,      // [{ path, originalFilename, contentType, sizeBytes }, ...]
    receivedAt        : datetime,   // when the source claimed the message arrived
    raw               : struct      // pass-through of the source payload for audit
}
```

Hand the normalized struct to `TicketsService` to create or append. The host loop-guard, blacklist check (`ChannelsService.isBlocked`), reply-matching, and duplicate detection happen between `normalizeInbound` and `TicketsService.createTicket` / `addMessage` in the existing core pipeline; new adapters can reuse that pipeline or implement their own pre-checks. Bypassing `ChannelsService.isBlocked` is not recommended.

### Polling cadence and outbound

Pull-based adapters do NOT manage their own timers. The host scheduler iterates the registry via `ChannelAdapterRegistry.pollAll()` and invokes each pull-based adapter's `pollOnce()` once per cycle.

Outbound dispatch is currently routed via the existing `OutboundEmailInterceptor` (which knows how to call `OutboundEmailService` for the email channel). Generalizing it into a generic `OutboundDispatchInterceptor` that resolves the right adapter by ticket source and calls `adapter.sendOutbound()` is a Phase 5 follow-up. Today, add-on adapters dispatch by registering their own listener on the relevant `onTicket*` events.

---

