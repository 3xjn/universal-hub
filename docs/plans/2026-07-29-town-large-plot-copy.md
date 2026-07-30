# Town Large Plot Copy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Copy every supported part in a Town source plot without an arbitrary Universal Hub size cap, while providing truthful estimates and progress, durable crash-safe resume/discard recovery, bounded memory, and no duplicate status presentation.

**Architecture:** Split the current monolithic Town copy path into a pure, JSON-safe copy planner, a private dual-slot checkpoint store, and a cooldown-aware execution engine behind the existing Town adapter. The planner writes and verifies the complete source plan, persists `awaiting_confirmation`, and waits for an explicit **Start copy** action before the first Town/F3X mutation; the engine then journals a pending batch before each mutation, reconciles that batch after interruption, and advances only confirmed work. The Town panel is the sole copy status/progress surface; the global Hub status remains adapter-level context.

**Tech Stack:** Luau, Roblox/Town instances and F3X `SyncAPI`, executor-local file APIs, `HttpService` JSON, Drawing-based `Overlay`, Lune contract tests, `luau-lsp`.

---

## Gate and scope

This document is plan-only. Do not modify production source, invoke Town/F3X/save/wiring remotes, create or destroy game instances, or move the player until the next gate is explicitly authorized.

Current authority is local implementation and verification only. Tasks 1-8 must remain uncommitted and unpublished: do not stage, commit, push, or open a PR. Any publication step is a separate gate that requires explicit manager/user authorization after implementation and QA review.

The implementation must:

- remove `MAX_PARTS` and every production `maxParts`/`limit` truncation path;
- allow a started job to end only as complete, safely paused/recoverable, or explicitly discarded/cleaned;
- never report a truncated prefix as a successful copy;
- reject only at a real input, storage, context, or game/API boundary;
- serialize and verify the complete source plan before the first game mutation;
- persist `awaiting_confirmation`, show exact counts/work/ETA, and require **Start copy** before the first game mutation;
- persist confirmed progress after every mutating batch;
- resume without duplicating parts or child instances after any crash window;
- keep memory bounded by plan and operation chunks rather than source size;
- preserve the existing save-name boundary of 1-32 letters, numbers, dashes, or underscores;
- never expose checkpoint paths or raw checkpoint contents in the UI;
- use one canonical copy status/progress surface.

## Live evidence captured on 2026-07-29

### Environment

- Volt daemon: reachable.
- Roblox: connected and paired.
- Experience: Town, `gameId = 1718755273`, `placeId = 4991214437`.
- Job observed: `b01f957f-e0b1-46d7-ada5-a5485a5647a5`.
- Read-only Luau evaluation: available.
- No game mutation or remote invocation was used for this evidence.

### Requested selected source is no longer live

The prior source that produced 18,791 supported snapshots is not present in the current server. The current Hub owner field is empty, no Hub copy/status text is live, and no current plot has 18,791 supported parts. Therefore its owner, class histograms, marker count, and group count cannot be re-measured without rejoining/reselecting that source. Do not manufacture those missing values from the previous count.

Current live source candidates:

| Owner | Supported parts | Total descendants |
|---|---:|---:|
| `s806647` | 8,434 | 37,978 |
| `Vixtrall` | 6,126 | 19,672 |
| `Marvo013` | 217 | 989 |
| `ArthurAlekseevich` | 142 | 1,071 |
| `spider_spooder7` | 129 | 516 |
| `Wearenothorseweare6` | 50 | 223 |
| `Rousthew3` | 10 | 58 |

The largest currently available source was measured exactly with the current `Town.partType`, wiring-marker, and `snapshotModels` rules:

- Owner: `s806647`
- Path: `Workspace.Private Building Areas.s806647BuildArea.Build`
- Total descendants: 37,978
- BaseParts: 8,434
- Supported: 8,434
- Unsupported: 0
- Supported ClassName histogram: `Part = 8,142`, `WedgePart = 251`, `Seat = 41`
- Unsupported ClassName histogram: empty
- Marker-bearing supported parts: 1,959
  - Marker rule: a direct `Texture` child with `abs(Transparency) >= 499.999`
- Model/group snapshots: 488
- Repeated Instance references in the supported array: 0

The earlier 2,054 “texture-bearing” count was deliberately superseded by the exact 1,959 wiring-marker count above; ordinary textures are not wiring markers.

### API and limit evidence

Read-only metadata found Town/F3X `RemoteFunction` instances such as `Building Tools.SyncAPI.ServerEndpoint` and save/settings endpoints. These instances expose no attributes declaring a numeric plot-size, property-batch, or total-operation limit.

Treat the current constants according to their actual meaning:

| Boundary | Treatment |
|---|---|
| 2,000 total supported parts | Delete. This is only a Universal Hub policy ceiling and has no documented rationale. |
| 513 Clone sources per request | Preserve conservatively as the existing adapter/request boundary, named `cloneRequestSize = 513`, pending a separately authorized disposable live probe. It is not yet a proven API limit and is never a total-job cap. |
| 128 property/rollback items | Keep initially as `preferredBatchSize = 128`, a scheduler tuning value pending the same authorized live probe. It is not a proven API or game limit. |
| `BuildCooling` | Wait before every F3X invocation; check cancellation while waiting. This is the live readiness boundary. |
| 6 seconds between Town commands | Preserve for command scheduling, especially `!savegui` then `!wireconnections`. |
| Save name 1-32 allowed characters | Preserve as a real Town save contract. |

For the current 8,434-part candidate, creation alone is 3 seed calls plus 38 Clone calls under the existing type distribution; `SyncResize` is 66 preferred 128-item batches. For 18,791 all-one-type parts, creation is one seed plus 45 Clone calls and `SyncResize` is 147 preferred batches. These are work estimates, not reasons to reject the job.

### Evidence gaps to close only in separately authorized QA

- Rejoin/reselect the 18,791-part source and repeat the exact read-only metrics.
- Measure F3X cooldown and round-trip distributions on a disposable owned plot; no read-only metadata publishes them.
- Probe Clone behavior at and around 513 and property/rollback behavior at and around 128 on a disposable owned plot. Record the exact result before either value is described in code, docs, or UI as a real API limit.
- Confirm whether mutating endpoints are all-or-nothing when interrupted; the recovery design below assumes they may be partially applied.
- Verify executor `writefile`, `readfile`, `isfile`, `delfile`, `makefolder`, and `listfiles` behavior. Persistent copy is disabled before mutation if any required capability is unavailable.
- Run live UI QA after the Hub panel is loaded; the duplicate status finding is currently static-code evidence.

## Product and safety decisions

### 1. Resume is primary; rollback is recovery

Choose resumable checkpoints over “rollback everything on every error.”

Why:

- a large job can span hundreds of cooldown-bound calls;
- disconnects can interrupt rollback exactly as they interrupt forward work;
- a successful remote call and a local checkpoint write cannot be one transaction;
- preserving confirmed work is faster and safer than recreating it;
- explicit discard can still clean up plan-owned instances in bounded batches.

On cancellation or recoverable error, stop at the next batch boundary and retain the checkpoint. Offer **Resume** and **Discard**. **Discard** means “clean plan-owned destination state, then delete the checkpoint,” not “forget the checkpoint immediately.”

If cleanup is incomplete, retain the checkpoint in `rollback_incomplete`; disable Resume; show **Retry cleanup**. Never delete the recovery record while plan-owned state may remain.

### 2. No Hub cap and no truncation

`CopyPlan.compile` accepts 2,000, 2,001, 18,791, and larger supported arrays. It does not accept `maxParts` or `limit`. A storage-capability or serialization failure aborts before game mutation with an actionable error. It never silently copies a prefix.

### 3. Mutation atomicity is per reconciled batch

Whole-job atomicity is impossible across Town remotes. The externally observable guarantee is:

1. persist the complete immutable source plan;
2. persist batch intent as `pendingBatch`;
3. invoke at most one mutating remote;
4. reconcile the destination;
5. persist confirmation and clear `pendingBatch`;
6. proceed to the next batch.

Progress counts only confirmed batches. A pending batch may have applied, but never contributes to the confirmed percentage until reconciliation succeeds.

### 4. One canonical status/progress surface

The Town in-panel phase text, percentage, progress bar, context line, and recovery actions are canonical.

`games/Town.lua` must stop copying `plotCopy.phase` into global `state.status`. `init.lua` must stop routing Town copy validation errors through the global status. The global header remains stable adapter context such as `Town ready`; it may show unrelated Hub/session failures, but never a Town copy phase or the same copy error.

Secondary Town text may show distinct context only: counts, work units, ETA range, source/destination compatibility, `last confirmed` versus `possibly applied`, or the required recovery action.

Canonical state mapping:

| State | Canonical Town phase | Distinct context | Actions | Global Hub status |
|---|---|---|---|---|
| `idle` | `Ready` | Selected owner/save name | `Copy & Save` | `Town ready` |
| `error` | `Copy blocked` | Specific cause and safe next action | `Retry` when valid | `Town ready` |
| `preflight` | `Preparing copy` | `scanned/total`, supported/unsupported, plan bytes | `Cancel` | `Town ready` |
| `awaiting_confirmation` | `Plan secured` | Exact counts, calls/batches, plan bytes, and ETA range/confidence | `Start copy`, `Cancel` | `Town ready` |
| `copy_authorized` | `Starting copy` | `Start confirmed; waiting for the first safe batch` | disabled | `Town ready` |
| `copying` | Operation phase, for example `Shaping geometry` | `batch x/y`, overall confirmed %, ETA | `Cancel` | `Town ready` |
| `cancel_requested` | `Cancel requested` | `Finishing current batch safely` | disabled | `Town ready` |
| `paused` / detected authorized checkpoint | `Copy paused` | Last confirmed batch and any possibly-applied batch | `Resume`, `Discard` | `Town ready` |
| `reconciling` | `Checking previous work` | Pending batch identity and reconciliation result | `Cancel` | `Town ready` |
| `resuming` | `Resuming copy` | Confirmed work and next batch | `Cancel` | `Town ready` |
| `discarding` | `Discarding checkpoint` | Context verification before cleanup | disabled | `Town ready` |
| `rollback` | `Cleaning copied parts` | Removed/remaining plan-owned items | disabled | `Town ready` |
| `rollback_incomplete` | `Recovery required` | Cleanup failure and retained checkpoint | `Retry cleanup` | `Town ready` |
| `saving` | `Saving copy` | Save name and confirmation state | `Cancel` only before invoke | `Town ready` |
| `completed` | `Copy complete` | Parts/groups/textures/lights and save name | `Copy another` | `Town ready` |

Automated UI contracts must compare the global status text with every visible Town status/context string and assert that no normalized non-empty message is duplicated.

An `awaiting_confirmation` checkpoint always recovers to the same **Start copy** / **Cancel** choice after relaunch. A `copy_authorized` checkpoint means the player already chose **Start copy**: if the process stopped before the first remote, relaunch maps it to an authorized paused job with **Resume** / **Discard**, not a second Start confirmation.

## Persistent checkpoint design

### Exact private storage and ownership

Default root:

```text
universal-hub/private/town-copy/<LocalPlayer.UserId>/
```

Files:

```text
state.a.json
state.b.json
plan-<jobId>-00001.json
plan-<jobId>-00002.json
...
quarantine/<quarantineId>/...
```

Allow a test/development override only through `UniversalHubConfig.TownCopyCheckpointRoot`; never render either path in the UI or logs.

Ownership is the local Roblox `UserId`, adapter id `town`, `gameId`, and `placeId`. A checkpoint from another user or adapter is never opened as resumable.

The checkpoint is local application privacy, not encryption. Persist only the source plan and recovery metadata required by this feature:

- no executor credentials, cookies, tokens, Volt data, chat, or unrelated Hub settings;
- owner name/user id, plot identities/fingerprints, transformed build properties, group/wiring metadata, save name, work graph, batch journal, and timing samples only;
- never expose raw JSON, raw paths, or full serialized part data in UI/error strings.

### Required file capabilities

Construct `TownCopyCheckpoint` in `init.lua` with injected `readfile`, `writefile`, `isfile`, `delfile`, `makefolder`, and `listfiles`, plus JSON encode/decode.

If any required function is unavailable:

- show `Persistent recovery is unavailable in this executor`;
- do not call F3X, Town commands, save, or wiring;
- do not offer an unsafe non-persistent fallback.

### Schema/versioning

Use `schemaVersion = 1`, `adapterId = "town"`, and `planVersion = 1`.

State record:

```lua
{
    schemaVersion = 1,
    adapterId = "town",
    planVersion = 1,
    generation = 42,
    job = {
        id = "<GUID>",
        state = "awaiting_confirmation",
        createdAt = 0,
        lastUpdatedAt = 0,
        originJobId = "<Roblox JobId>",
    },
    context = {
        gameId = 1718755273,
        placeId = 4991214437,
        localUserId = 0,
        source = {
            ownerName = "",
            ownerUserId = 0,
            plotName = "",
            plotPath = "",
            fingerprint = "",
        },
        destination = {
            ownerName = "",
            ownerUserId = 0,
            plotName = "",
            plotPath = "",
            plotFrame = {},
            plotSize = {},
            baselineFingerprint = "",
        },
    },
    request = {
        saveName = "",
        copyWiring = false,
    },
    authorization = {
        state = "awaiting_confirmation",
        confirmedAt = nil,
    },
    plan = {
        chunkCount = 0,
        chunkChecksums = {},
        supported = 0,
        unsupported = 0,
        groups = 0,
        work = {},
        totalWeight = 0,
    },
    progress = {
        phase = "create",
        lastConfirmedSequence = 0,
        lastConfirmedBatchId = nil,
        confirmedWeight = 0,
        pendingBatch = nil,
        timing = {},
    },
    cleanup = {
        state = "not_requested",
        lastConfirmedSequence = 0,
        pendingBatch = nil,
    },
}
```

Plan chunks contain JSON-safe values only. Replace every live `Instance` reference with deterministic `partId`/`modelId` membership. Serialize CFrames, vectors, colors, enums, surfaces, mesh, texture, light, marker, source fingerprint fields, transformed destination values, and operation records. No raw `Instance` reference crosses the preflight boundary.

### Canonical serialization and checksum API

Create `games/town/Canonical.lua`. Do not checksum raw `HttpService:JSONEncode` output because object key order is not guaranteed.

API:

```lua
Canonical.encode(value) -> string
Canonical.sha256Bytes(bytes) -> string
Canonical.checksum(value) -> string
Canonical.verify(value, expected) -> boolean
```

`Canonical.checksum(value)` returns:

```text
sha256-c14n-v1:<64 lowercase hexadecimal digits>:<canonical byte length>
```

Canonical serialization rules:

1. Accepted values are booleans, finite numbers, valid UTF-8 strings, dense arrays, and objects with string keys. `nil`/JSON null is not serializable: omit an optional object key or use an explicit schema field such as `state = "absent"`. Reject functions, userdata, sparse/mixed tables, NaN, and infinities before writing.
2. Dense arrays have exactly integer keys `1..n` and encode in index order as JSON arrays.
3. Objects have string keys only. Sort keys by unsigned UTF-8 byte sequence and encode in that order.
4. Strings use JSON quoting: escape quotation mark, backslash, and control characters; encode U+0000-U+001F as lowercase `\u00xx`; preserve all other valid UTF-8 bytes.
5. Normalize `-0` to `0`. Encode integers in base 10 without leading zeroes. Encode non-integers with `string.format("%.17g", value)`, lowercase the exponent, remove `+`, and remove redundant leading exponent zeroes. Tests must pin these transformations in both Lune and live Luau before mutation QA.
6. Use no insignificant whitespace.
7. Compute SHA-256 over the canonical UTF-8 bytes with a pure Luau FIPS 180-4 implementation using `bit32`, returning lowercase hex. Do not depend on executor-specific `crypt` APIs.

Stored JSON is an envelope:

```lua
{
    format = "uh-town-checkpoint",
    checksumAlgorithm = "sha256-c14n-v1",
    checksum = Canonical.checksum(payload),
    payload = payload,
}
```

Verification decodes JSON, validates the fixed format/algorithm strings, canonicalizes only `payload`, recomputes the checksum, and compares the entire algorithm/hash/length token. The checksum field never hashes itself. Plan chunk checksums, state-slot checksums, source fingerprints, destination fingerprints, and work-graph fingerprints all use this same API.

### Complete-plan-before-mutation protocol

1. Read-only scan the source with a deterministic depth-first iterator.
2. Buffer at most 256 supported part/model records.
3. Write each immutable plan chunk.
4. Read it back, decode it, verify job id/index/count/checksum, then release its buffer.
5. Compile exact work totals and fingerprints.
6. Write and verify state generation 1 with `state = "awaiting_confirmation"` and all chunk checksums.
7. Re-read every referenced chunk header/checksum.
8. Publish exact counts, calls/batches, plan bytes, and ETA range/confidence with **Start copy** and **Cancel**.
9. Make zero Town/F3X/command/save/wiring remote calls while `awaiting_confirmation`.
10. On **Cancel**, delete the untouched job checkpoint and return to idle.
11. On **Start copy**, persist and verify `authorization.state = "copy_authorized"` before journaling or invoking the first mutating batch.
12. Only after verified authorization may the engine persist the first `pendingBatch` and invoke its remote.

If preflight fails at any point, remove its staging files and make zero game mutations.

### Atomic state writes without rename assumptions

Do not assume executor file rename is atomic.

For every state transition:

1. read both state slots and select the highest valid generation;
2. encode generation + 1 into the inactive/older slot;
3. `writefile` that slot;
4. `readfile`, decode, validate the envelope, and verify the canonical SHA-256 checksum, schema, generation, and job id;
5. keep the previous valid slot untouched.

On load, choose the highest fully valid generation. A partial/corrupt newest slot falls back to the previous slot. This yields record-level atomicity without an atomic rename primitive.

Plan chunks are immutable and written once. Progress updates never rewrite the full 18k+ source plan.

### Retention, deletion, and quarantine

- `completed`: delete both state slots and every referenced plan chunk immediately after save/wiring confirmation and final UI state publication.
- successful `discard`: delete only after destination cleanup confirms no plan-owned items remain.
- `paused`, recoverable `error`, or `rollback_incomplete`: retain for 7 days after `lastUpdatedAt`.
- at 7 days: disable Resume, privately quarantine raw files, show only sanitized `Checkpoint expired; discard recovery data`.
- quarantine retention: 7 additional days, then delete automatically.
- corrupt or version-mismatched state: never resume. Move/copy files into the private quarantine directory, validate the quarantine copy, remove active slots, and show a sanitized discard/recovery message.
- context mismatch: do not mutate and do not overwrite. Keep the checkpoint paused while the expected destination may reappear; if the mismatch is structural or version-related, quarantine it.
- orphan plan chunks with no valid state: quarantine by restricted root enumeration; never interpret them as an active job.

### Resume compatibility

Before Resume, verify:

- schema and adapter/plan versions;
- `game.GameId` and `game.PlaceId`;
- local Roblox `UserId`;
- destination plot name, owner, path, CFrame/Size fingerprint, and `Build` identity;
- destination inventory equals `baseline + confirmed plan-owned work + at most one pending batch`;
- source owner/user id and persisted source fingerprint;
- if the source is still present, its fresh fingerprint must match;
- if the source has left, the already complete persisted plan is sufficient;
- requested save name and wiring mode;
- no foreign destination changes since the last confirmed boundary.

`Roblox JobId` is audit context, not a resume equality requirement; relaunch/rejoin necessarily changes it.

Any ambiguity blocks mutation and preserves the checkpoint.

## Batch identity and reconciliation

Batch ids are deterministic:

```text
<jobId>:<phase>:<zero-padded-sequence>
```

Persist exactly one `pendingBatch`:

```lua
{
    id = "<jobId>:create:000042",
    sequence = 42,
    phase = "create",
    operation = "Clone",
    planIds = { "part-001024", "part-001025" },
    expectedBefore = { ... },
    expectedAfter = { ... },
}
```

Rules by operation:

- **CreatePart/Clone:** persist destination baseline and expected type/count delta. After interruption, adopt exactly matching unclaimed destination parts; if zero appeared, retry; if a partial exact delta appeared, adopt it and issue a new batch for the remainder; if foreign or ambiguous parts appeared, stop with recovery required. Never blindly replay Clone.
- **Set-style property batches:** `SyncResize`, color, material, surface, collision, and anchor are idempotent. Reconcile live values; reissue only missing/mismatched records.
- **Meshes, textures, and lights:** identify intended children by parent `partId` plus type/face/property fingerprint. Adopt one exact match, create only missing children, and stop on duplicates/ambiguity.
- **Groups:** identify a planned group by the exact set of child part/model ids and expected hierarchy. Adopt one exact membership match; create only when none exists; stop if multiple candidates match.
- **Wiring:** if the destination `Wired` attribute is already true and group fingerprints match, confirm without reissuing. Otherwise wait for command cooldown and invoke once.
- **Save:** persist save intent and previous save entry/`LastEdited` marker. On resume, confirm an updated/new matching entry before retrying. Never create a second save name.
- **Rollback Remove:** use the same pending/confirmed journal and the initial 128-item scheduler tuning size. Reconcile absence after each batch.

Checkpoint confirmation must happen immediately after live reconciliation, before UI progress advances.

## Scheduler, progress, cancellation, and estimates

### Exact preflight work model

The planner must report:

- total descendants;
- BasePart count;
- supported/unsupported count and ClassName histograms;
- part types;
- marker-bearing count;
- mesh, texture/decal, enabled-light, and model/group counts;
- exact CreatePart seeds and Clone calls by type using the conservative existing 513 request size;
- exact records and preferred batch counts for every property/child/group phase;
- wiring and save terminal work;
- serialized chunk count and bytes;
- rollback work units.

No number is based on `MAX_PARTS`, and no phase disappears merely to make the estimate smaller.

### Time estimates without false precision

Before mutation:

- show exact planned remote call/batch counts;
- show scan/serialization elapsed time measured during preflight;
- derive an ETA range from separately validated Town cooldown/round-trip samples;
- if no validated sample exists, label time confidence `uncalibrated` and show the formula/work count rather than inventing a precise duration.

During mutation:

- maintain EWMA and p90 duration per operation class from confirmed batches;
- update an ETA range from remaining work;
- persist timing aggregates in the checkpoint so relaunch progress remains truthful;
- do not persist a cross-job player profile.

### Explicit post-preflight confirmation

Preflight completion is not mutation authorization.

1. After all chunks and the initial state are verified, persist `awaiting_confirmation`.
2. Render the exact supported/unsupported counts, operation and preferred-batch counts, plan bytes, ETA range, and confidence label.
3. Offer only **Start copy** and **Cancel**.
4. While this state is active, fake and live contract counters for SyncAPI, Town commands, save, and wiring must all remain zero.
5. Relaunch from this state restores the same plan summary and **Start copy** / **Cancel** choice.
6. **Cancel** deletes the unmutated checkpoint and returns to idle.
7. **Start copy** writes and verifies `copy_authorized` before the first pending batch or remote.
8. A crash after `copy_authorized` but before the first pending batch/remote recovers as an already-authorized paused job. It offers **Resume** / **Discard**, never a second **Start copy** prompt.
9. Resume from that crash state issues the first remote exactly once; the pre-crash remote count remains zero.

### Progress

Replace magic fixed percentages with persisted work weights:

```lua
overallProgress = confirmedWeight / totalWeight
phaseProgress = phaseConfirmed / phaseTotal
```

Weights come from measured/validated operation duration classes. Until calibrated, use one unit per remote batch plus measured local scan/serialization units. Overall progress is monotonic and based on confirmed work only.

The store shape should include:

```lua
plotCopy = {
    state = "copying",
    active = true,
    phase = "Shaping geometry",
    phaseCompleted = 17,
    phaseTotal = 147,
    confirmedProgress = 0.42,
    possiblyAppliedBatch = nil,
    context = "Batch 17/147 · about 12-18 min remaining",
    resumeAvailable = false,
    discardAvailable = false,
}
```

### Cancellation safe points

- A Cancel click sets `cancelRequested` immediately and publishes `cancel_requested`.
- Never interrupt an in-flight remote.
- Check cancellation while waiting for `BuildCooling`, immediately before a remote, and after reconciliation/checkpoint confirmation.
- At the safe boundary, persist `paused`, close only Hub-opened transient save UI, and offer Resume/Discard.
- Cancellation during preflight or `awaiting_confirmation` deletes the unmutated checkpoint after local deletion confirmation.
- Once `copy_authorized` is persisted, cancellation/unload pauses the authorized checkpoint even if no remote has run; recovery uses **Resume** / **Discard**.
- Cancellation after mutation retains the checkpoint; it does not auto-rollback.
- Unload/`Session:stop()` requests cancellation and performs no new forward mutation. Because every remote has pre-journaled intent, a hard unload remains recoverable.

### Error and terminal cleanup

- On disconnect, unload, timeout, endpoint error, or save/wiring error, persist a sanitized error plus pending-batch state.
- Destroy only a save GUI that Universal Hub opened, never a pre-existing player GUI.
- Disconnect all listeners and stop scheduler tasks on unload.
- Save and wiring remain terminal phases.
- A confirmed save marks the job complete, publishes completion, then deletes the checkpoint.
- If final checkpoint deletion fails, show `Copy complete; local recovery cleanup pending` and retry deletion without repeating save/copy work.

## Implementation tasks

### Task 1: Lock no-cap planning and exact work estimates

**Files:**

- Create: `games/town/CopyPlan.lua`
- Create: `games/town/Canonical.lua`
- Create: `tests/town_canonical_contracts.luau`
- Create: `tests/town_copy_plan_contracts.luau`
- Modify: `hub.lua:27-46`
- Modify: `scripts/check.sh:23-66`

**Step 1: Write failing canonical and pure-plan contracts**

Pin canonical key sorting, arrays, escaping, normalized numbers, finite-number rejection, standard SHA-256 vectors, and `sha256-c14n-v1` tokens before the plan fingerprint tests.

Create fixtures with exactly 2,000, 2,001, 18,791, and 25,000 supported records. Assert:

```lua
assert(CopyPlan.compile(fixture(2000)).supported == 2000)
assert(CopyPlan.compile(fixture(2001)).supported == 2001)
assert(CopyPlan.compile(fixture(18791)).supported == 18791)
assert(CopyPlan.compile(fixture(25000)).supported == 25000)
assert(CopyPlan.compile(fixture(18791)).truncated == nil)
```

Also assert exact type histograms, marker count, group membership, unsupported histogram, Clone requests `<= 513` under the existing conservative adapter request size, 147 resize batches for 18,791 records at scheduler tuning size 128, deterministic ids/fingerprint, and maximum chunk buffer `<= 256`. Test names and messages must not call either request size a proven API limit.

**Step 2: Run the focused test and verify it fails**

Run:

```bash
lune run tests/town_canonical_contracts.luau
lune run tests/town_copy_plan_contracts.luau
```

Expected: FAIL because `games/town/Canonical.lua` and `games/town/CopyPlan.lua` do not exist.

**Step 3: Implement canonical serialization, SHA-256, and the pure planner**

Implement the exact canonical/checksum API first. `CopyPlan.fingerprint` must call `Canonical.checksum`; it must not define a second serialization or hash algorithm.

Export:

```lua
CopyPlan.compile(sourceContext, options)
CopyPlan.iterChunks(plan, chunkSize)
CopyPlan.fingerprint(records)
CopyPlan.cloneCallCount(count)
CopyPlan.estimateWork(plan, preferredBatchSize)
```

Do not accept `maxParts` or `limit`. Convert all live values to JSON-safe records and deterministic ids.

**Step 4: Register and validate**

Add `games/town/Canonical.lua` and `games/town/CopyPlan.lua` to `hub.lua` and LSP inputs, and add both tests to `scripts/check.sh`.

Run both focused tests; expect `town-canonical-contracts-ok` and `town-copy-plan-contracts-ok`.

**Step 5: Leave changes local**

Record focused-test evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 2: Add private atomic checkpoint storage

**Files:**

- Create: `games/town/CheckpointStore.lua`
- Create: `tests/town_checkpoint_contracts.luau`
- Modify: `hub.lua`
- Modify: `scripts/check.sh`

**Step 1: Write failing storage contracts**

Use an in-memory fake filesystem. Cover:

- checksum mismatch and byte-length mismatch rejection;
- exact per-user private root;
- no raw path/content in returned UI errors;
- immutable chunk write/readback verification;
- state generation dual-slot selection;
- partial newest write falls back to previous state;
- corrupt both slots quarantines and blocks resume;
- schema/adapter/plan version mismatch;
- wrong game/place/user/destination/source fingerprint;
- stale active state and quarantine retention;
- completion/discard deletion;
- missing file capability blocks before mutation;
- no credential/secret keys in the schema.

**Step 2: Run and verify failure**

```bash
lune run tests/town_checkpoint_contracts.luau
```

Expected: FAIL because `CheckpointStore` does not exist.

**Step 3: Implement the storage boundary**

Use `Canonical.checksum` and `Canonical.verify` from Task 1 for every state envelope, plan chunk, and context/work fingerprint.

Export:

```lua
CheckpointStore.new(options)
store:stagePlan(job, chunkIterator)
store:commitInitial(state)
store:load(context)
store:advance(mutator)
store:quarantine(reason)
store:deleteJob()
store:prune(now)
```

Use only injected file/JSON functions. Validate every write by rereading and recomputing the canonical checksum after JSON decode. Sanitize every public error.

**Step 4: Run focused and full storage tests**

Expected: `town-checkpoint-contracts-ok`.

**Step 5: Leave changes local**

Record focused-test evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 3: Enforce preflight-before-mutation and cooldown-aware batches

**Files:**

- Create: `games/town/CopyEngine.lua`
- Create: `tests/town_copy_engine_contracts.luau`
- Modify: `hub.lua`
- Modify: `scripts/check.sh`

**Step 1: Write failing engine contracts**

With fake SyncAPI, cooling, command, filesystem, and destination:

- 2,000/2,001/>18k plans reach persisted `awaiting_confirmation`;
- storage failure makes zero SyncAPI/command/save/wiring calls;
- initial state/chunks are verified before first mutation;
- exact counts/work/ETA are published with **Start copy** and **Cancel**;
- relaunch from `awaiting_confirmation` restores the same choice;
- no remote runs before **Start copy**;
- **Cancel** from `awaiting_confirmation` deletes the untouched checkpoint with zero remotes;
- **Start copy** persists and verifies `copy_authorized` before the first `pendingBatch`;
- Clone calls never exceed the existing conservative 513 adapter request size;
- preferred property/rollback batches use the 128 scheduler tuning size;
- every call waits for cooling;
- confirmed state is persisted after every batch;
- progress advances only after confirmation;
- ETA and work counts match remaining batches;
- no plan truncation.

Record an ordered event log and assert:

```lua
assert(indexOf("checkpoint:awaiting_confirmation") < indexOf("ui:start_copy"))
assert(remoteCountBefore("user:start_copy") == 0)
assert(indexOf("user:start_copy") < indexOf("checkpoint:copy_authorized"))
assert(indexOf("checkpoint:copy_authorized") < indexOf("checkpoint:pending:create:1"))
assert(indexOf("checkpoint:pending:create:1") < indexOf("remote:create:1"))
assert(indexOf("checkpoint:confirmed:create:1") < indexOf("progress:create:1"))
```

**Step 2: Run and verify failure**

```bash
lune run tests/town_copy_engine_contracts.luau
```

Expected: FAIL because `CopyEngine` does not exist.

**Step 3: Implement the engine skeleton and scheduler**

Export:

```lua
CopyEngine.new(context)
engine:preflight(request)
engine:confirmStart()
engine:requestCancel()
engine:stop()
```

Centralize one `runBatch` path that journals, waits, invokes, reconciles, confirms, and publishes progress.

**Step 4: Run focused tests**

Expected: `town-copy-engine-contracts-ok`.

**Step 5: Leave changes local**

Record focused-test evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 4: Make crash windows idempotent

**Files:**

- Modify: `games/town/CopyEngine.lua`
- Modify: `tests/town_copy_engine_contracts.luau`

**Step 1: Add failing crash-window contracts**

For every mutating operation, simulate:

1. crash after `copy_authorized` persistence but before the first `pendingBatch` or remote;
2. crash after `pendingBatch` persistence but before remote;
3. crash after partial/complete remote effect but before checkpoint confirmation;
4. crash after checkpoint confirmation but before UI update.

Assert:

- Create/Clone never duplicates;
- the post-Start/pre-first-remote crash has zero pre-crash remote calls;
- relaunch maps that authorized job to **Resume** / **Discard**, not a second **Start copy** confirmation;
- Resume from that state issues the first remote exactly once;
- set-style batches reapply only missing values;
- texture/light/group reconciliation adopts exactly one match;
- ambiguous foreign destination changes block mutation;
- saved/wired terminal work is detected rather than repeated;
- `lastConfirmedBatch` and `possiblyAppliedBatch` stay distinct and truthful.

**Step 2: Run and verify failure**

Expected: duplicate or ambiguous replay assertions fail.

**Step 3: Implement operation-specific reconciliation**

Add reconcilers for create, set-property, child creation, group membership, wiring, save, and remove. All return one of:

```lua
"not_applied", "partially_applied", "confirmed", "ambiguous"
```

Only `not_applied` may be retried unchanged. `partially_applied` produces a new remainder batch. `ambiguous` stops safely.

**Step 4: Run focused tests**

Expected: all crash-window and duplicate-prevention contracts pass.

**Step 5: Leave changes local**

Record crash-window evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 5: Add cancellation, resume, discard, and reliable cleanup

**Files:**

- Modify: `games/town/CopyEngine.lua`
- Modify: `games/town/CheckpointStore.lua`
- Modify: `tests/town_copy_engine_contracts.luau`
- Modify: `tests/town_checkpoint_contracts.luau`

**Step 1: Write failing lifecycle contracts**

Cover:

- cancel during cooling;
- cancel during an in-flight remote;
- unload with a pending batch;
- relaunch from `awaiting_confirmation` restores **Start copy** / **Cancel** with zero remotes;
- relaunch from `copy_authorized` before the first remote restores authorized **Resume** / **Discard**;
- relaunch detects compatible paused job;
- Resume reconciles then continues;
- Discard verifies context then removes in bounded batches;
- cleanup interruption resumes without duplicate Remove;
- incomplete rollback retains checkpoint and exposes Retry cleanup;
- completion deletes all active chunks/slots;
- save/wiring GUI/listener cleanup;
- corrupt/stale/version-mismatched checkpoints never mutate.

**Step 2: Run and verify failure**

Expected: lifecycle assertions fail before implementation.

**Step 3: Implement lifecycle state transitions**

Export:

```lua
engine:inspectRecovery()
engine:resume()
engine:discard()
engine:retryCleanup()
```

Check cancellation at every safe point. Preserve the checkpoint until cleanup or completion is proven.

**Step 4: Run focused tests**

Expected: checkpoint and engine lifecycle tests pass.

**Step 5: Leave changes local**

Record lifecycle evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 6: Integrate the engine into the Town adapter and Hub lifecycle

**Files:**

- Modify: `games/Town.lua:14-17`
- Modify: `games/Town.lua:297-989`
- Modify: `init.lua:40-53`
- Modify: `init.lua:137-177`
- Modify: `init.lua:212-368`
- Modify: `tests/town_adapter_contracts.luau`
- Modify: `tests/session_contracts.luau`

**Step 1: Write failing adapter contracts**

Assert:

- `MAX_PARTS`, `maxParts`, and production `limit` are absent;
- copy requests delegate to preflight/engine;
- storage APIs and exact private root are injected;
- `stop()` requests a safe pause and never begins new mutation;
- recovery is inspected on startup;
- adapter exposes preflight, confirm-Start, cancel, resume, discard, and retry-cleanup commands;
- global `status` is not patched with Town copy phase/error.

**Step 2: Run and verify failure**

```bash
lune run tests/town_adapter_contracts.luau
lune run tests/session_contracts.luau
```

Expected: FAIL on missing engine/recovery integration and existing duplicate status patches.

**Step 3: Replace the monolithic path with the facade**

Keep Town discovery and game matching in `games/Town.lua`; delegate planning, persistence, and execution to the new modules. Inject:

```lua
readFile, writeFile, isFile, deleteFile, makeFolder, listFiles,
jsonEncode, jsonDecode, generateGuid, now
```

Do not retain the legacy fallback copy implementation.

**Step 4: Run adapter/session tests**

Expected: both focused suites pass.

**Step 5: Leave changes local**

Record adapter/session evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 7: Make the Town panel the only copy status surface

**Files:**

- Modify: `modules/Overlay.lua:302-419`
- Modify: `modules/Overlay.lua:421-600`
- Modify: `modules/Overlay.lua:1542-1572`
- Modify: `modules/Overlay.lua:1711-1745`
- Modify: `init.lua:212-253`
- Modify: `tests/overlay_contracts.luau:1040-1176`

**Step 1: Write failing state-mapping and duplicate-message contracts**

Render every canonical state:

- error;
- preflight;
- awaiting confirmation with exact counts/work/ETA and **Start copy** / **Cancel**;
- copy authorized/starting;
- copying;
- cancel requested/paused;
- resume detected/reconciling/resuming;
- discard;
- rollback/cleanup incomplete;
- saving;
- completion.

Assert correct phase, context, confirmed percent, action labels, enabled actions, and colors. Normalize visible strings and assert the global status does not equal or contain the Town phase/context/error.

**Step 2: Run and verify failure**

```bash
lune run tests/overlay_contracts.luau
```

Expected: FAIL because current `publishProgress` writes the same phase to global status and Town progress.

**Step 3: Implement canonical rendering and actions**

Add distinct Town context and action controls for **Start copy**, Cancel, Resume, Discard, and Retry cleanup. Wire **Start copy** to `confirmStart`; it must not rerun preflight. Keep the global status fixed at adapter/session context. Route Town validation errors into `plotCopy.state = "error"` only.

**Step 4: Run overlay tests**

Expected: `overlay-contracts-ok`, including explicit absence of duplicate messages.

**Step 5: Leave changes local**

Record UI state-mapping and duplicate-message evidence in the implementation handoff. Do not stage, commit, push, or publish.

### Task 8: Run automated validation

**Files:**

- Modify only files required to fix failures introduced by Tasks 1-7.

**Step 1: Run all focused contracts**

```bash
lune run tests/town_copy_plan_contracts.luau
lune run tests/town_canonical_contracts.luau
lune run tests/town_checkpoint_contracts.luau
lune run tests/town_copy_engine_contracts.luau
lune run tests/town_adapter_contracts.luau
lune run tests/overlay_contracts.luau
lune run tests/session_contracts.luau
```

Expected: all print their `*-ok` sentinel and exit 0.

**Step 2: Run the repository check**

```bash
./scripts/check.sh
```

Expected: `universal-hub-check-ok`.

**Step 3: Review changed behavior**

Confirm no arbitrary total cap, no truncation, no raw checkpoint UI text, no duplicate copy status, and no unjournaled mutating remote path.

**Step 4: Preserve manager review state**

Confirm all implementation changes remain local and uncommitted. Do not stage, commit, push, open a PR, or otherwise publish until the manager/user explicitly authorizes a separate publication gate.

### Task 9: Staged manual QA with separate mutation authorization

**Files:** None unless QA finds a defect.

**Step 1: Read-only preflight gate**

With the reselected >18k source:

- verify owner/path and exact requested histograms;
- run preflight-only mode;
- confirm complete plan chunks/state are written and verified;
- confirm F3X/command/save/wiring call counters remain zero;
- confirm exact batch/work estimates and uncalibrated/calibrated ETA labeling;
- confirm the UI shows **Start copy** and **Cancel** and does not start automatically;
- unload/relaunch and verify the same **Start copy** / **Cancel** choice with zero remotes;
- choose **Cancel** and verify checkpoint deletion with zero remotes;
- verify raw paths/content never appear.

Stop here unless disposable owned-plot mutation is separately authorized.

**Step 2: Disposable small-plot mutation gate**

After explicit authorization:

- use an empty owned destination;
- rerun preflight, verify `awaiting_confirmation`, then choose **Start copy**;
- force a crash immediately after verified `copy_authorized` persistence and before the first remote; verify zero pre-crash remotes, **Resume** / **Discard** recovery, no second Start prompt, and exactly one first remote after Resume;
- probe Clone request sizes around 513, including 512/513/514 where safe;
- probe property/rollback request sizes around the 128 scheduler tuning value;
- record exact accepted/rejected/partial/error results before calling either number a real API limit anywhere;
- measure cooling/round-trip samples;
- cancel after a confirmed batch and Resume;
- force the post-remote/pre-checkpoint crash window and verify no duplicate;
- Discard and verify complete cleanup;
- force cleanup interruption and verify Retry cleanup.

**Step 3: Disposable 2,000 and 2,001 gates**

Verify both complete without a Hub rejection and without truncation. Compare source/created counts and fingerprints.

**Step 4: Disposable >18k gate**

Verify:

- all supported parts are planned and created;
- property, child, group, wiring, and save phases finish;
- progress/ETA remain truthful;
- unload/relaunch resume works;
- memory stays within the 256-record planning buffer plus bounded live batch state;
- checkpoint files are deleted on completion;
- the global status never duplicates the Town panel.

**Step 5: Failure-path gate**

Exercise disconnect, source departure after plan capture, destination mismatch, corrupt newest slot, both slots corrupt, stale/version mismatch, save failure, wiring failure, and incomplete rollback. Verify zero wrong-plot mutation and retained recovery data where cleanup is incomplete.

## Definition of done for the implementation gate

- 2,000, 2,001, 18,791, and larger fixtures are accepted without truncation.
- A complete verified private source plan exists before the first game mutation.
- Verified preflight persists `awaiting_confirmation`, displays exact work/ETA, and makes zero remotes until **Start copy**.
- Relaunch from `awaiting_confirmation` restores **Start copy** / **Cancel**; relaunch after Start persistence but before the first remote restores authorized **Resume** / **Discard** without duplicate calls.
- Every mutating batch has pending intent, reconciliation, and durable confirmation.
- A job ends only complete, safely paused/recoverable, or explicitly discarded/cleaned; a truncated prefix is never reported as success.
- Resume never duplicates parts, textures, lights, groups, wiring, or saves.
- Cancellation and unload stop at safe boundaries.
- Discard removes plan-owned work before deleting recovery data.
- Corrupt, stale, incompatible, and version-mismatched checkpoints cannot mutate.
- Progress reflects confirmed work, including across relaunch.
- Town panel is the only copy-state/progress surface.
- Automated checks pass.
- Tasks 1-8 remain local, uncommitted, and unpublished pending explicit manager/user publication authorization.
- Read-only preflight QA passes before any mutation QA.
- Separately authorized disposable owned-plot QA passes through >18k.
