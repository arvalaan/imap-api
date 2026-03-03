# Task 1 Expansion: First-Class Label API for Proton Bridge

## Context

For Proton Bridge-backed accounts, assigning a label is done by moving a message to a mailbox path under `Labels/`.

- Example: moving a message to `Labels/To-Process` assigns the label `To-Process`
- Therefore, API-level "labeling" should be implemented as mailbox move semantics (single-label assignment per move operation), with clear behavior and safeguards for automation clients like n8n.

## Goal

Introduce explicit label-focused endpoints so workflow tools do not need to encode provider-specific logic in every workflow.

## Proposed API design

### 1) Single message label assignment

`POST /v1/account/{account}/message/{message}/labels/assign`

Payload:

```json
{
  "label": "To-Process",
  "prefix": "Labels"
}
```

Rules:

- `label` is required
- final destination path is `${prefix}/${label}` (default `prefix = "Labels"`)
- operation maps to `messageMove(uid, destinationPath)` internally
- response includes the destination path and new message id (if uid remap returned)

Response shape:

```json
{
  "id": "AAAA...",
  "assigned": true,
  "label": "To-Process",
  "destination": "Labels/To-Process",
  "messageId": "BBBB..."
}
```

### 2) Bulk label assignment

`POST /v1/account/{account}/messages/labels/assign`

Payload:

```json
{
  "messages": ["AAAA...", "CCCC..."],
  "label": "To-Process",
  "prefix": "Labels"
}
```

Rules:

- group by source mailbox internally (same strategy as `bulkMoveMessages`)
- move in batches by UID per source mailbox
- per-message outcomes for n8n branch handling

Response shape:

```json
{
  "assigned": 2,
  "failed": 0,
  "destination": "Labels/To-Process",
  "messages": [
    {
      "id": "AAAA...",
      "assigned": true,
      "messageId": "BBBB..."
    }
  ]
}
```

### 3) Optional label provisioning endpoint (recommended)

`PUT /v1/account/{account}/label`

Payload:

```json
{
  "label": "To-Process",
  "prefix": "Labels",
  "ensure": true
}
```

Rules:

- resolves destination path `Labels/To-Process`
- creates mailbox when absent
- idempotent return

Response shape:

```json
{
  "path": "Labels/To-Process",
  "created": true,
  "existing": false
}
```

## Validation and normalization requirements

- reject empty label names
- trim leading/trailing whitespace
- reject path separators in `label` (or strictly sanitize)
- canonicalize destination with `normalizePath`
- protect against moves to same folder (return `assigned: true, noop: true`)

## Execution model details

- Reuse existing account->connection->mailbox call flow:
  - `workers/api.js` route + Joi schema
  - `lib/account.js` convenience methods
  - `lib/connection.js` destination resolution and grouping
  - `lib/mailbox.js` move execution
- Keep existing endpoints fully backward compatible:
  - `POST /message/{id}/move`
  - `POST /messages/move`
  - `PUT /message/{id}` with `path`

## n8n-focused behavior

To keep workflows deterministic:

- always return per-message results in bulk operations
- include both old `id` and any remapped `messageId`
- do not fail entire batch if one message fails
- include machine-readable `error` values for branch logic

## Suggested error taxonomy

- `InvalidLabelName`
- `LabelPathNotAllowed`
- `DestinationMailboxMissing`
- `SourceMailboxNotFound`
- `MessageNotFound`
- `MoveFailed`

## Documentation updates to include with implementation

- Proton-specific note: "Assigning a label is implemented as move to `Labels/<Label>`"
- 3 curl examples:
  1. ensure label mailbox
  2. assign label to one message
  3. assign label to many messages
- n8n recipe:
  - Trigger/webhook -> filter messages -> bulk label assign -> inspect failures

## Why this expansion matters

This converts provider-specific behavior into explicit API contracts and reduces workflow complexity. n8n workflows can call a stable "assign label" operation instead of re-implementing path logic and edge-case handling per flow.
