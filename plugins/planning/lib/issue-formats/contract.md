## Contract Definition

**Type:** {API spec / data schema / event format / interface definition / protocol}

**Name:** {short identifier for this contract}

## Context

This contract is needed because the following features/issues depend on a shared {type}:

## Dependent Issues

- #{N} {title} — consumes: {which part of the contract}
- #{N} {title} — consumes: {which part of the contract}

## Must define

- {specific thing the contract must specify — field names, types, endpoints, message format}
- {validation rules, error formats, versioning strategy}
- {example request/response or sample payload}

## Deliverable location

{Where the contract will live — e.g., `docs/contracts/recipe-ingest.md`, an OpenAPI spec, a `.proto` file, a shared types module.}

## Acceptance Criteria

Concrete, verifiable checklist of what the contract artifact must contain and what dependent wiring must exist. No GWT — this is a specification deliverable, not a user-interaction slice.

### Artifact
- [ ] File exists at {Deliverable location}
- [ ] Defines all fields/endpoints/messages listed in Must define
- [ ] Includes versioning strategy
- [ ] Includes at least one example usage

### Dependent wiring

Applied automatically by `/update-milestone` contract reconciliation, OR by hand if running standalone. Tick once verified (not just planned):

- [ ] Every issue in Dependent Issues has `BLOCKED BY #{this_contract}` in its Dependencies section (verified via milestone audit or manual inspection)
- [ ] Every sub-issue of dependents references this contract in Contract compliance (verified)
- [ ] `blocked` label applied to every dependent issue (verified)

### Review
- [ ] Contract reviewed and approved by {reviewer / team}

## Test Criteria

- [ ] [local-test] Contract file exists at the deliverable location
- [ ] [human-verify] Contract reviewed and approved
- [ ] [subtask-check] Every dependent issue has blocked-by marker and matching sub-issues that reference this contract
- [ ] [ci-check] CI pipeline passes (if contract is code — types/schema/proto)

**Important:** This contract MUST be completed and merged before any dependent issue begins work. Dependent issues are tagged with `blocked` label and `BLOCKED BY #{this_issue}` in their body.
