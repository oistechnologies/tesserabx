## Using Example Sync

Example Sync is a reference add-on bundled with TesseraBX that demonstrates every extension point a third-party module can plug into. It is intentionally a stub: every external call returns canned data, the channel adapter does not actually deliver anything, and the AI feature replies with placeholder text.

You will see it in two places:

- The **Example Sync** main-menu entry on the agent dashboard links to the connection-settings page.
- The **External link** card on the right column of every ticket detail page is where a linked external issue would render. With no real integration configured, the card shows "none".

### Linking a ticket

Either from the agent dashboard or from an automation rule, choose the **Link to an external issue** action and pick a project key. The add-on records the link in the `tickets_example_sync` extension table and fires the `exampleSync.issue_linked` event so any subscribed webhook + notification fan-out activates.

### Removing the add-on

Drop the `sample-addons/example-sync` folder; the registries will simply stop surfacing its contributions on next app boot. No core data is left behind unless you actually linked tickets (in which case the `tickets_example_sync` table rows persist; drop the migration if you want them gone).
