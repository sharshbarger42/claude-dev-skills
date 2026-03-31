# Gitea MCP: URL Parsing Guide

When the user gives you a Gitea actions URL, the numbers in the URL do NOT match the IDs the MCP API expects.

**URL format:** `https://{host}/{owner}/{repo}/actions/runs/{run_number}/jobs/{job_index}`

**CRITICAL: `run_number` ≠ `run_id`, and `job_index` ≠ `job_id`.** You MUST resolve them.

**Procedure:**

1. **Parse the URL** — extract `owner`, `repo`, `run_number`, and `job_index`
2. **Find the internal run ID** — call `actions_run_read` with `method: "list_runs"`, `owner`, `repo`. Find the run where `run_number` matches the URL number. Use its `id` field for subsequent calls.
3. **Get jobs** — call `actions_run_read` with `method: "list_run_jobs"`, `owner`, `repo`, `run_id: <internal id from step 2>`
4. **Select the job** — pick the job at the positional index from the URL (`/jobs/0` = first job). Use its `id` field as `job_id`.
5. **Get logs** — call `actions_run_read` with `method: "get_job_log_preview"`, `owner`, `repo`, `job_id: <id from step 4>`

**DO NOT** pass the run number from the URL directly as `run_id`.
