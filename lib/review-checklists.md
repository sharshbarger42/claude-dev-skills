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
- Missing tests or docs where warranted

## Pass 3: Standards Compliance
- Repo-specific rules from Review Standards section
- Commit message format
- File placement and naming conventions
- Hardcoded values that should be variables

## Pass 4: Edge Cases & Robustness
- Missing input validation / boundary checks
- Off-by-one errors
- Empty/null/undefined handling
- External call failure modes
- Timeout and retry considerations
- Backwards compatibility
