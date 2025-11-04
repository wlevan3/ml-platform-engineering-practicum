---
description: Analyze all PR reviews and comments from any reviewer/bot and create a prioritized remediation plan
argument-hint: <PR_NUMBER>
allowed-tools: Bash(gh:*)
---

# Analyze PR Reviews

Fetch all code reviews and comments from a GitHub PR (from any reviewer/bot), analyze their
validity, and create a plan to address valid feedback.

## Usage

```text
/analyze-pr-reviews <PR_NUMBER>
```

## Arguments

- `<PR_NUMBER>`: The GitHub PR number to analyze (required)

## What This Command Does

1. **Switches to PR branch**: Automatically checks out the PR's branch for proper context (stashes changes if needed)
2. **Fetches all reviews**: Uses GitHub API to retrieve all code reviews from the PR (any reviewer, any state)
3. **Fetches all comments**: Gets inline review comments on specific files/lines AND general PR discussion comments
4. **Extracts review feedback**: Aggregates code reviews, inline comments, and discussion threads
5. **Analyzes validity**: Determines if each piece of feedback is:
   - Technically sound and identifies real issues or improvements
   - Actionable (specific action can be taken)
   - Relevant (relates to actual code changes in this PR)
   - Not duplicative or contradictory
   - Following project conventions and standards
6. **Creates action plan**: For valid feedback, develops a prioritized plan to address it

## Reviewers Captured

This command captures feedback from:

- **AI Code Reviewers**: Copilot, CodeRabbit, etc.
- **Security Bots**: Dependabot, Snyk, etc.
- **Human Reviewers**: Any GitHub user who left a review

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Current directory is a git repository
- PR exists on GitHub

## Example

```text
/analyze-pr-reviews 42
```

This analyzes all reviews and comments on PR #42 from any reviewer.

---

## Task: Analyze All PR Reviews and Comments

**IMPORTANT**: Replace `ARGUMENTS` with the PR number provided by the user.

You need to analyze ALL code reviews, review comments, and discussion feedback from PR **ARGUMENTS** in the current repository.

### Step 0: Switch to PR Branch

Before analyzing reviews, switch to the PR's branch to have proper context:

1. **Get PR branch name**:

```bash
gh pr view ARGUMENTS --json headRefName --jq '.headRefName'
```

1. **Handle uncommitted changes** (if any):

```bash
# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD --; then
  echo "Stashing uncommitted changes..."
  git stash push -m "WIP: Switching to PR #ARGUMENTS for review analysis"
fi
```

1. **Fetch and checkout PR branch**:

```bash
# Get the branch name first
BRANCH_NAME=$(gh pr view ARGUMENTS --json headRefName --jq '.headRefName')

# Check if branch exists locally
if git show-ref --verify --quiet refs/heads/$BRANCH_NAME; then
  # Branch exists locally, just checkout
  git checkout $BRANCH_NAME
  # Pull latest changes
  git pull origin $BRANCH_NAME
else
  # Branch doesn't exist locally, fetch and checkout
  git fetch origin $BRANCH_NAME
  git checkout $BRANCH_NAME
fi
```

**Note**: After analysis is complete, you can return to the original branch if needed.

### Step 1: Get Repository Information

First, determine the repository owner and name:

```bash
gh repo view --json owner,name --template '{{.owner.login}}/{{.name}}'
```

Store the result as `OWNER/REPO` for subsequent commands.

### Step 2: Fetch All Review Data

Run these three commands in parallel to fetch all review data sources:

**A. PR Review Summaries (all states: APPROVED, CHANGES_REQUESTED, COMMENTED):**

```bash
gh api repos/OWNER/REPO/pulls/ARGUMENTS/reviews \
  --jq '.[] | {type: "review_summary", id: .id, state: .state, user: .user.login, user_type: .user.type, body: .body, submitted_at: .submitted_at, html_url: .html_url}'
```

**B. Inline Review Comments (file/line-specific discussion threads):**

```bash
gh api repos/OWNER/REPO/pulls/ARGUMENTS/comments \
  --jq '.[] | {type: "inline_comment", id: .id, user: .user.login, user_type: .user.type, body: .body, path: .path, line: .line, position: .position, created_at: .created_at, html_url: .html_url}'
```

**C. PR Discussion Comments (general comments):**

```bash
gh api repos/OWNER/REPO/issues/ARGUMENTS/comments \
  --jq '.[] | {type: "discussion_comment", id: .id, user: .user.login, user_type: .user.type, body: .body, created_at: .created_at, html_url: .html_url}'
```

**Do NOT filter** by reviewer name or type - capture ALL feedback.

### Step 3: Organize Feedback

Combine all three data sources and organize by:

1. **Reviewer** (group all feedback from the same reviewer together)
2. **Source type** (review summary vs inline comment vs discussion comment)
3. **Review state** (APPROVED, CHANGES_REQUESTED, COMMENTED)

For each piece of feedback, extract:

- Reviewer name and type (Bot or User)
- Review state (if applicable)
- Comment ID
- File path and line number (if applicable)
- Full comment text
- Timestamp
- GitHub URL

### Step 4: Analyze Each Comment

For each piece of feedback, evaluate against these criteria:

**Validity Assessment:**

- ✅ **Technically Sound**: Does it identify a real issue or improvement?
- ✅ **Actionable**: Is there a specific action the developer can take?
- ✅ **Relevant**: Does it relate to the actual code changes in this PR?
- ✅ **Not Duplicate**: Is it unique (not repeated elsewhere)?
- ✅ **Standards-Aligned**: Does it align with project conventions?

**Classification:**

- **APPROVAL BLOCKER** - Changes requested; must fix before merge
- **VALID** - Should address in this PR
- **PARTIALLY VALID** - Can address, but may need context
- **INFORMATIONAL** - Approval or general comment; no action needed
- **INVALID** - Dismiss or defer to future work
- **NEEDS CLARIFICATION** - Requires more context to understand

### Step 5: Create Remediation Plan

For **APPROVAL BLOCKER**, **VALID**, and **PARTIALLY VALID** feedback:

1. **Categorize** by type:
   - Security vulnerabilities
   - Performance issues
   - Code quality/style
   - Testing gaps
   - Documentation needs
   - Architecture concerns

2. **Prioritize** by urgency:
   - **P0: Blockers** - Must fix to merge (APPROVAL BLOCKER items)
   - **P1: Critical** - Should fix in this PR
   - **P2: Important** - Should fix soon
   - **P3: Nice-to-have** - Can defer

3. **Create action items** with:
   - Specific file/line references
   - Clear description of what needs to change
   - Estimated effort (quick/moderate/substantial)
   - Implementation guidance

4. **Order** by logical dependency and priority

### Step 6: Present Results

Display a comprehensive analysis in this format:

```markdown
## PR Review Analysis - PR #ARGUMENTS

### Executive Summary
- **Total reviews**: X
- **Total comments**: Y (inline: A, discussion: B)
- **Reviewers**: [list of all reviewers]
- **Review states**: APPROVED (X), CHANGES_REQUESTED (Y), COMMENTED (Z)
- **Merge status**: ✅ Ready / ⚠️ Blockers present

### Approval Status

**Approvals** (X):
- [Reviewer 1]
- [Reviewer 2]

**Changes Requested** (Y):
- [Reviewer 3] - N blocking comments
- [Reviewer 4] - M blocking comments

**Comments Only** (Z):
- [Reviewer 5] - P comments

### Detailed Feedback by Reviewer

#### [Reviewer Name] ([Bot/Human])
**Review State**: APPROVED / CHANGES_REQUESTED / COMMENTED
**Total Comments**: N

##### Review Summary
[Main review feedback if present]

##### Inline Comments (X)
1. **File**: `path/to/file.ext` (Line X)
   - **Comment**: [Full comment text]
   - **Classification**: [VALID/INVALID/etc]
   - **Analysis**: [Brief analysis of validity]
   - **URL**: [GitHub link]

##### Discussion Comments (Y)
1. **Comment**: [Full comment text]
   - **Classification**: [VALID/INVALID/etc]
   - **Analysis**: [Brief analysis]
   - **URL**: [GitHub link]

[Repeat for all reviewers...]

### Remediation Plan

#### P0: Blockers (Must Fix to Merge) - X items

1. **[Category]** - [File/Line Reference]
   - **Issue**: [Description from review]
   - **Action**: [Specific fix needed]
   - **Effort**: [Quick/Moderate/Substantial]
   - **From**: [Reviewer name]

[Additional blockers...]

#### P1: Critical (Should Fix in PR) - X items

[Same format as blockers...]

#### P2: Important (Should Fix Soon) - X items

[Same format...]

#### P3: Nice-to-Have (Can Defer) - X items

[Same format...]

### Statistics

- **Total actionable items**: X
- **By category**:
  - Security: X
  - Performance: X
  - Code quality: X
  - Testing: X
  - Documentation: X
  - Other: X
- **By priority**:
  - P0 (Blockers): X
  - P1 (Critical): X
  - P2 (Important): X
  - P3 (Nice-to-have): X

### Recommendations

**For This PR:**
1. [Specific recommendation based on feedback patterns]
2. [Another recommendation]

**Process Improvements:**
1. [Suggestion to improve review process]
2. [Another process suggestion]
```

### Important Notes

- **Do NOT make code changes** - only analyze and create plan
- **Reference specific line numbers** from reviews when creating action items
- **Group related feedback** if multiple reviewers mention the same issue
- **Be objective** in validity assessment - explain reasoning
- **Preserve context** by including links to original review comments
- **Distinguish** between blocking feedback (CHANGES_REQUESTED) and optional suggestions
