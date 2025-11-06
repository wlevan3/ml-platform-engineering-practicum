#!/bin/bash
# Fetch all code reviews and comments from a GitHub PR
# Includes: review summaries (any reviewer, any state), inline review comments, and PR discussion comments
# Usage: fetch-pr-reviews.sh <PR_NUMBER>

set -euo pipefail

# Check if PR number provided
if [[ $# -ne 1 ]]; then
	echo "Usage: fetch-pr-reviews.sh <PR_NUMBER>"
	echo ""
	echo "Fetches ALL reviews and comments from a GitHub PR:"
	echo "  - PR review summaries (from any reviewer, any state: APPROVED, CHANGES_REQUESTED, COMMENTED)"
	echo "  - Inline review comments (discussion threads on specific files/lines)"
	echo "  - PR discussion comments (general comments)"
	exit 1
fi

PR_NUMBER="$1"

# Get repository information
REPO_INFO=$(gh repo view --json owner,name --template '{{.owner.login}}/{{.name}}')
OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)

echo "Repository: $OWNER/$REPO"
echo "PR Number: $PR_NUMBER"
echo ""

# ============================================================
# Fetch 1: PR Review Summaries (ANY state, ANY reviewer)
# ============================================================
echo "Fetching PR review summaries..."
REVIEWS=$(gh api repos/"$OWNER"/"$REPO"/pulls/"$PR_NUMBER"/reviews \
	--jq '.[] | {
        type: "review_summary",
        id: .id,
        state: .state,
        user: .user.login,
        user_type: .user.type,
        body: .body,
        submitted_at: .submitted_at,
        commit_id: .commit_id,
        html_url: .html_url
    }' 2>/dev/null || echo "[]")

REVIEW_COUNT=$(echo "$REVIEWS" | jq -s 'length')

# ============================================================
# Fetch 2: Inline Review Comments (ANY reviewer)
# ============================================================
echo "Fetching inline review comments..."
REVIEW_COMMENTS=$(gh api repos/"$OWNER"/"$REPO"/pulls/"$PR_NUMBER"/comments \
	--jq '.[] | {
        type: "inline_comment",
        id: .id,
        user: .user.login,
        user_type: .user.type,
        body: .body,
        path: .path,
        position: .position,
        commit_id: .commit_id,
        created_at: .created_at,
        html_url: .html_url
    }' 2>/dev/null || echo "[]")

INLINE_COUNT=$(echo "$REVIEW_COMMENTS" | jq -s 'length')

# ============================================================
# Fetch 3: PR Discussion Comments (ANY reviewer)
# ============================================================
echo "Fetching PR discussion comments..."
PR_COMMENTS=$(gh api repos/"$OWNER"/"$REPO"/issues/"$PR_NUMBER"/comments \
	--jq '.[] | {
        type: "discussion_comment",
        id: .id,
        user: .user.login,
        user_type: .user.type,
        body: .body,
        created_at: .created_at,
        html_url: .html_url
    }' 2>/dev/null || echo "[]")

DISCUSSION_COUNT=$(echo "$PR_COMMENTS" | jq -s 'length')

# ============================================================
# Combine and Display Results
# ============================================================
TOTAL_COUNT=$((REVIEW_COUNT + INLINE_COUNT + DISCUSSION_COUNT))

if [[ $TOTAL_COUNT -eq 0 ]]; then
	echo ""
	echo "No reviews or comments found for PR #$PR_NUMBER"
	exit 0
fi

echo ""
echo "Found reviews and comments:"
echo "  - Review summaries: $REVIEW_COUNT"
echo "  - Inline comments: $INLINE_COUNT"
echo "  - Discussion comments: $DISCUSSION_COUNT"
echo "  - TOTAL: $TOTAL_COUNT"
echo ""
echo "============================================================"
echo ""

# Display review summaries
if [[ $REVIEW_COUNT -gt 0 ]]; then
	echo "### PR REVIEW SUMMARIES"
	echo ""
	echo "$REVIEWS" | jq -r '.[] | @json' | while read -r review; do
		review=$(echo "$review" | jq -r '.')
		ID=$(echo "$review" | jq -r '.id')
		STATE=$(echo "$review" | jq -r '.state')
		USER=$(echo "$review" | jq -r '.user')
		USER_TYPE=$(echo "$review" | jq -r '.user_type')
		BODY=$(echo "$review" | jq -r '.body')
		SUBMITTED=$(echo "$review" | jq -r '.submitted_at')
		COMMIT=$(echo "$review" | jq -r '.commit_id')
		URL=$(echo "$review" | jq -r '.html_url')

		echo "[Review #$ID] ($STATE)"
		echo "User: $USER ($USER_TYPE)"
		echo "Submitted: $SUBMITTED"
		echo "Commit: ${COMMIT:0:7}"
		echo "URL: $URL"
		echo ""
		echo "Body:"
		echo "$BODY"
		echo ""
		echo "---"
		echo ""
	done
fi

# Display inline review comments
if [[ $INLINE_COUNT -gt 0 ]]; then
	echo "### INLINE REVIEW COMMENTS"
	echo ""
	echo "$REVIEW_COMMENTS" | jq -r '.[] | @json' | while read -r comment; do
		comment=$(echo "$comment" | jq -r '.')
		ID=$(echo "$comment" | jq -r '.id')
		USER=$(echo "$comment" | jq -r '.user')
		USER_TYPE=$(echo "$comment" | jq -r '.user_type')
		BODY=$(echo "$comment" | jq -r '.body')
		PATH=$(echo "$comment" | jq -r '.path')
		POSITION=$(echo "$comment" | jq -r '.position')
		COMMIT=$(echo "$comment" | jq -r '.commit_id')
		CREATED=$(echo "$comment" | jq -r '.created_at')
		URL=$(echo "$comment" | jq -r '.html_url')

		echo "[Inline Comment #$ID]"
		echo "User: $USER ($USER_TYPE)"
		echo "File: $PATH"
		echo "Position: $POSITION"
		echo "Commit: ${COMMIT:0:7}"
		echo "Created: $CREATED"
		echo "URL: $URL"
		echo ""
		echo "Body:"
		echo "$BODY"
		echo ""
		echo "---"
		echo ""
	done
fi

# Display PR discussion comments
if [[ $DISCUSSION_COUNT -gt 0 ]]; then
	echo "### PR DISCUSSION COMMENTS"
	echo ""
	echo "$PR_COMMENTS" | jq -r '.[] | @json' | while read -r comment; do
		comment=$(echo "$comment" | jq -r '.')
		ID=$(echo "$comment" | jq -r '.id')
		USER=$(echo "$comment" | jq -r '.user')
		USER_TYPE=$(echo "$comment" | jq -r '.user_type')
		BODY=$(echo "$comment" | jq -r '.body')
		CREATED=$(echo "$comment" | jq -r '.created_at')
		URL=$(echo "$comment" | jq -r '.html_url')

		echo "[Discussion Comment #$ID]"
		echo "User: $USER ($USER_TYPE)"
		echo "Created: $CREATED"
		echo "URL: $URL"
		echo ""
		echo "Body:"
		echo "$BODY"
		echo ""
		echo "---"
		echo ""
	done
fi

echo "============================================================"
echo "Total reviews and comments found: $TOTAL_COUNT"
