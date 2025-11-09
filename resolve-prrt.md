# Resolve PRRT jq guardrails

When collecting and summarizing PRRT threads we frequently stitch together multiple GraphQL responses, which leaves us with newline-separated JSON documents instead of one cohesive JSON array. Two common jq errors crop up because of that:

1. **`jq: syntax error, unexpected INVALID_CHARACTER …`** — usually from using `jq` on a filter file that contains unescaped quotes or newline characters that the shell already tried to interpolate. Always create filters via a literal heredoc (e.g., `cat <<'EOF' > summary.jq`) so jq sees raw syntax, or better: write the filter inline with single quotes so the shell never tries to escape `\n`, `\"`, etc.

2. **`jq: error: Cannot index string with string "isOutdated"`** — happens because the `gh api` output was appended line-by-line and we never wrapped it into a JSON array. jq's `.[]` expects an array, but the file looks like:

   ```text
   {"something": …}
   {"something": …}
   ```

   Use `jq -s '.[].data.repository.pullRequest.reviewThreads.nodes[] | …'` or `jq -s '[.[] | <normalize> ]'` to slurp the newline-delimited documents into a single array before applying `.[]`.

## Suggested workflow

```bash
THREADS_FILE=$(mktemp)
SUMMARY_FILTER=$(mktemp)

# collect pages unchanged
…

# normalize all nodes into a single JSON array
jq -s '[.[] | .data.repository.pullRequest.reviewThreads.nodes[]]' "$THREADS_FILE" > "${THREADS_FILE}.array"

# write a filter with a literal heredoc to avoid shell quoting issues
cat <<'EOF' > "$SUMMARY_FILTER"
.[] | select(.id | startswith("PRRT_")) | {
  id,
  path: (.path // "N/A"),
  line: (.line // "N/A"),
  isResolved,
  isOutdated,
  comments: (.comments.nodes // [])
}
EOF

# emit a compact summary
jq -r -f "$SUMMARY_FILTER" "${THREADS_FILE}.array"
```

Following these two habits (slurping before iterating and keeping jq scripts literal) avoids the reported jq errors and keeps the `/resolve-prrt` workflow stable moving forward.
