# contacts

Responsibility, owned entities, public service interface, and events for the `contacts` module.

The `contacts` module is the foundational module. It owns the tenant-boundary entities
(`Organization`, `Office`, `Contact`) and the Quick global scope (`TenantScope`) that enforces
row-scoped isolation. Most other modules depend on it and reach its data through
`ContactsService` rather than touching its entities directly.

See [CLAUDE.md](../../CLAUDE.md) for hard constraints and [docs/BUILD-PLAN.md](../../docs/BUILD-PLAN.md) for the phased build order.

## Owned entities

- **Organization** - the tenant boundary (one client company). Attributes: name, slug, tier,
  status (prospect/active/suspended/archived), is_active, account_number, phone, website, industry,
  full mailing address, timezone, notes, primary_contact_id, and auto_provision_contacts (drives
  approved-domain contact auto-creation). No global scope: agents see all organizations.
- **Office** - a full location record within an organization (name, address, phone, timezone,
  is_primary/HQ flag). Tenant-scoped.
- **Contact** - a client-side user account. Belongs to one Organization and optionally one Office.
  Attributes include profile fields (phone, mobile_phone, job_title, timezone, locale), is_vip,
  notes, source (agent/portal/domain-auto/import/email), and TOTP MFA columns. Tenant-scoped, and
  the cbauth user entity for the portal surface.
- **ContactRole** - client-side role assignments (e.g. organization-admin).
- **OrganizationDomain** - approved email domains mapped to an organization, each with an
  is_verified flag. Used by channel intake to route and auto-provision.

## Public service interface (`ContactsService`)

Organizations: `getOrganizationById`, `getOrganizationBySlug`, `listOrganizations`,
`listOrganizationOptions`, `organizationCounts`, `createOrganization`, `updateOrganization`,
`setOrganizationActive`, `deactivateOrganization`.

Offices: `listOfficesForOrganization`, `getOfficeById`, `createOffice`, `updateOffice`,
`deleteOffice`.

Contacts: `getContactById`, `getContactByEmail`, `directoryFor`, `listContactsForOrganization`,
`provisionContact`, `updateContactProfile`, `deactivateContact`, `mergeContacts`, and
`resolveOrAutoProvisionContact` (the inbound-channel resolver, see below).

Roles: `listRolesForContact`, `assignRole`, `revokeRole`.

Approved domains: `resolveOrganizationForEmail`, `getDomainMapping`, `addDomainMapping`,
`setDomainVerified`, `removeDomainMapping`, `listDomainMappingsForOrganization`.

### `resolveOrAutoProvisionContact(email)`

The single place the tenant-assignment decision lives for inbound mail. The `channels` module
calls it instead of resolving contacts itself. It returns:

1. the existing Contact when the email is already known (global lookup; an email already owned by
   another org keeps that org);
2. otherwise, a newly provisioned Contact (source `domain-auto`) when the sender's domain is an
   approved domain that is verified, on an organization that is active and has
   `auto_provision_contacts` enabled;
3. otherwise null, so the caller falls back to an accountless ticket.

Note on persistence: Organizations and Offices have no jsonb columns, so create/update use Quick
`save()`. Contact writes must use the targeted `queryExecute` UPDATE in `updateContactProfile`
because `mfa_recovery_codes` (jsonb) is a PGobject after load and Quick `save()` cannot rebind it.

## Events emitted

`onOrganizationCreated`, `onOrganizationUpdated`, `onOrganizationDeactivated`,
`onOfficeCreated`, `onOfficeUpdated`, `onOfficeDeleted`,
`onContactProvisioned`, `onContactDeactivated`, `onContactRoleGranted`, `onContactRoleRevoked`,
`onContactMerged`, `onOrganizationDomainMapped`, `onOrganizationDomainUnmapped`.
