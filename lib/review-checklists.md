# Review Checklists

## Pass 1: Security & Correctness
- Injection vectors (command, SQL, template)
- Auth/authz gaps
- Secrets or credentials in code/config
- Bugs and logic errors
- Error handling gaps
- Data validation issues
- Race conditions, resource leaks

## Pass 2: Architecture & Design
- Design pattern adherence
- Code organization / separation of concerns
- Naming clarity
- Unnecessary complexity / over-engineering
- Code duplication worth extracting
- NOTE: Do NOT flag cleanups, refactors, or documentation updates as "scope creep." These are welcome in any PR. Only flag if a commit message references the wrong issue.

## Pass 3: Standards Compliance
- Repo-specific rules from Review Standards section
- Commit message format (only flag wrong issue numbers, not style preferences)
- File placement and naming conventions
- Hardcoded values that should be variables
- NOTE: Verify claims before making them. Check the actual base branch version, check if paths exist, check if patterns are documented. Do not assert "this is wrong" based on assumptions.

## Pass 4: Edge Cases & Robustness
- Missing input validation / boundary checks
- Off-by-one errors
- Empty/null/undefined handling
- External call failure modes
- Timeout and retry considerations
- Backwards compatibility
