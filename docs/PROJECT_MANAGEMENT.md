# GitHub Projects Setup Guide

This guide explains how to set up and use GitHub Projects to manage the ML Platform Engineering Practicum.

## Table of Contents

- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
- [Views Configuration](#views-configuration)
- [Custom Fields](#custom-fields)
- [Automation Workflows](#automation-workflows)
- [Workflows and Best Practices](#workflows-and-best-practices)

## Project Structure

### Overview

Use a single GitHub Project to track all work across the ML platform practicum:
- Infrastructure tasks
- Feature development
- Bug fixes
- Learning reflections
- Documentation
- Experiments and research

### Recommended Project Name

**"ML Platform Engineering Practicum"**

## Setup Instructions

### Step 1: Create the Project

1. Go to: `https://github.com/users/wlevan3/projects`
2. Click **"New project"**
3. Choose **"Start from scratch"** or use a template
4. Name it: **"ML Platform Engineering Practicum"**
5. Add description: *"End-to-end ML platform implementation tracker: EKS, model registry, feature store, CI/CD, observability, and learnings"*
6. Set visibility: **Public** or **Private** (your choice)
7. Click **"Create project"**

### Step 2: Link Repository

1. In your project, go to **Settings** (⚙️ icon)
2. Under **"Manage access"**, link the repository:
   - Repository: `wlevan3/ml-platform-engineering-practicum`
3. This allows automatic syncing of issues and PRs

### Step 3: Enable GitHub Actions Integration

1. Go to project **Settings** → **Workflows**
2. Enable built-in automation workflows (covered in Automation section)

## Views Configuration

Create multiple views to visualize work from different perspectives.

### View 1: Board (Status View)

**Purpose:** Track work status visually

**Setup:**
1. Click **"New view"** → **"Board"**
2. Name: **"Status Board"**
3. Group by: **Status**
4. Configure columns:
   - 📋 **Backlog** - Not started, low priority
   - 🎯 **Ready** - Planned for current phase
   - 🚧 **In Progress** - Currently working on
   - 👀 **In Review** - PR open, awaiting merge
   - ✅ **Done** - Completed
   - 🧊 **Blocked** - Waiting on external dependency

**Filter:** None (show all items)

### View 2: Component Board

**Purpose:** Organize by platform component

**Setup:**
1. Click **"New view"** → **"Board"**
2. Name: **"By Component"**
3. Group by: **Component** (custom field - see below)
4. Columns:
   - 🎯 EKS Cluster
   - 📦 Model Registry
   - 🗄️ Feature Store
   - 🔄 CI/CD Pipeline
   - 📊 Observability
   - 🏗️ Infrastructure
   - 📚 Documentation
   - 🧠 Learning

### View 3: Table (Detailed View)

**Purpose:** See all task details in spreadsheet format

**Setup:**
1. Click **"New view"** → **"Table"**
2. Name: **"Detailed Table"**
3. Visible columns:
   - Title
   - Status
   - Component
   - Priority
   - Complexity
   - Phase
   - Due Date
   - Assignee (you)
   - Labels

**Sort:** Priority (High → Low), then Status

### View 4: Roadmap (Timeline View)

**Purpose:** Plan work chronologically by phase

**Setup:**
1. Click **"New view"** → **"Roadmap"**
2. Name: **"Practicum Roadmap"**
3. Date field: **Phase** (custom iteration field)
4. Group by: **Component**
5. Zoom level: **Months** or **Quarters**

This gives you a Gantt-chart style view of your practicum timeline.

### View 5: Learning Reflections

**Purpose:** Filter and review learning entries

**Setup:**
1. Click **"New view"** → **"Table"**
2. Name: **"Learnings"**
3. Filter: `label:learning` OR `Component:Learning`
4. Sort: Newest first
5. Visible columns:
   - Title
   - Topic Area (custom field)
   - Date Created
   - Insights Summary

## Custom Fields

Add custom fields to track ML platform-specific metadata.

### How to Add Custom Fields

1. In any view, click **"+"** in the column header area
2. Select **"New field"**
3. Choose field type and configure

### Recommended Custom Fields

#### 1. Component (Single Select)

**Type:** Single select
**Options:**
- 🎯 EKS Cluster
- 📦 Model Registry
- 🗄️ Feature Store
- 🔄 CI/CD Pipeline
- 📊 Observability
- 🏗️ Infrastructure
- 📚 Documentation
- 🧠 Learning
- 🔧 Tooling
- 🔐 Security

#### 2. Priority (Single Select)

**Type:** Single select
**Options:**
- 🔴 Critical (blocking)
- 🟠 High (important)
- 🟡 Medium (nice to have)
- 🟢 Low (future)

**Color coding:** Red → Orange → Yellow → Green

#### 3. Complexity (Number)

**Type:** Number
**Range:** 1-5
**Description:**
- 1 = Very simple (< 1 hour)
- 2 = Simple (1-3 hours)
- 3 = Moderate (half day)
- 4 = Complex (1-2 days)
- 5 = Very complex (> 2 days)

#### 4. Phase (Iteration)

**Type:** Iteration
**Duration:** 2 weeks
**Suggested phases:**
- Phase 1: Foundation & Setup
- Phase 2: EKS & Kubernetes
- Phase 3: Model Registry
- Phase 4: Feature Store
- Phase 5: CI/CD Integration
- Phase 6: Observability
- Phase 7: Optimization & Polish

#### 5. Environment (Single Select)

**Type:** Single select
**Options:**
- 🧪 Development
- 🎭 Staging
- 🚀 Production
- 🌍 All Environments

#### 6. Infrastructure Type (Single Select)

**Type:** Single select
**Options:**
- Terraform
- Kubernetes
- Helm
- AWS Console
- Scripts
- N/A

#### 7. Cost Impact (Single Select)

**Type:** Single select
**Options:**
- 💰 High (> $50/month)
- 💵 Medium ($10-50/month)
- 💸 Low (< $10/month)
- ✅ None/Free Tier

#### 8. Topic Area (Single Select) - For Learning Items

**Type:** Single select
**Options:**
- Kubernetes/EKS
- Terraform/IaC
- CI/CD & GitOps
- ML Platform Architecture
- Feature Stores
- Model Registry
- Observability
- AWS Services
- Security & IAM
- Cost Optimization
- Platform Engineering

#### 9. Due Date (Date)

**Type:** Date
**Use:** Set target completion dates for critical tasks

#### 10. AWS Services (Text)

**Type:** Text
**Use:** List AWS services used (e.g., "EKS, RDS, S3")

## Automation Workflows

GitHub Projects supports built-in automation. Here are recommended workflows:

### Auto-add Issues and PRs

**Trigger:** When an issue or PR is opened
**Action:** Automatically add to project

**Setup:**
1. Go to project **Settings** → **Workflows**
2. Enable **"Auto-add to project"**
3. Configure:
   - Repository: `wlevan3/ml-platform-engineering-practicum`
   - Trigger: Issue or PR opened
   - Add to project: Yes

### Set Status on Creation

**Trigger:** Item added to project
**Action:** Set Status to "Backlog" or "Ready"

**Setup:**
1. Enable **"Item added to project"** workflow
2. Set field: **Status** = **Backlog**

### Set Status on PR Open

**Trigger:** PR is opened
**Action:** Set Status to "In Review"

**Setup:**
1. Enable **"Pull request opened"** workflow
2. Set field: **Status** = **In Review**

### Set Status on PR Merge

**Trigger:** PR is merged
**Action:** Set Status to "Done"

**Setup:**
1. Enable **"Pull request merged"** workflow
2. Set field: **Status** = **Done**

### Set Status on Issue Close

**Trigger:** Issue is closed
**Action:** Set Status to "Done"

**Setup:**
1. Enable **"Issue closed"** workflow
2. Set field: **Status** = **Done**

### Set Status on PR Close (not merged)

**Trigger:** PR is closed without merge
**Action:** Set Status back to "Ready" or "Backlog"

**Setup:**
1. Enable **"Pull request closed"** workflow
2. Set field: **Status** = **Backlog**

## Workflows and Best Practices

### Daily Workflow

1. **Check Status Board** - Review what's in progress
2. **Move 1 task** from "Ready" to "In Progress"
3. **Work on task** - Create branch, make changes
4. **Update project** - Add notes, update complexity if needed
5. **Create PR** - Automatically moves to "In Review"
6. **Self-review and merge** - Automatically moves to "Done"

### Weekly Workflow

1. **Review Roadmap view** - Check phase progress
2. **Triage Backlog** - Move high-priority items to "Ready"
3. **Add learning reflections** - Document insights from the week
4. **Plan next week** - Select tasks for upcoming phase
5. **Review metrics** - Check velocity (items completed per week)

### Creating New Work Items

#### From GitHub UI

```bash
# Create issue with template
gh issue create --template infrastructure.yml \
  --title "[Infra]: Setup EKS cluster" \
  --body "..."

# Issue automatically added to project
# Set Component, Priority, and Phase in project view
```

#### Directly in Project

1. Click **"+ Add item"** at bottom of any view
2. Type title (can convert to issue later)
3. Set fields: Component, Priority, Phase, etc.
4. Click **"Convert to issue"** to link to repository

### Linking Work

- Link related issues: Use `#123` in issue descriptions
- Link to PRs: Use `Closes #123` in PR description
- Link to documentation: Use full URLs
- Cross-reference learning reflections

### Organizing with Labels

Use labels in combination with project fields:

**Priority labels:** (redundant with field, but useful for filtering)
- `priority: critical`
- `priority: high`
- `priority: medium`
- `priority: low`

**Type labels:**
- `type: feature`
- `type: bug`
- `type: infrastructure`
- `type: documentation`
- `type: learning`

**Status labels:** (auto-synced with project Status field)
- `status: blocked`
- `status: needs-review`

## Example: Adding Your First Task

Let's add a sample task to get started:

### Via Project UI

1. Go to your "Status Board" view
2. In the **"Backlog"** column, click **"+ Add item"**
3. Type: `Setup initial EKS cluster with Terraform`
4. Press Enter
5. Click on the new item to open details
6. Set fields:
   - **Component:** 🎯 EKS Cluster
   - **Priority:** 🟠 High
   - **Complexity:** 4
   - **Phase:** Phase 2: EKS & Kubernetes
   - **Infrastructure Type:** Terraform
   - **Cost Impact:** 💰 High
7. Click **"Convert to issue"** (top-right)
8. Select repository: `wlevan3/ml-platform-engineering-practicum`
9. Issue is created and linked!

### Via GitHub Issue

1. Go to repository Issues
2. Click **"New issue"**
3. Choose **"Infrastructure Task"** template
4. Fill out the template
5. Click **"Submit new issue"**
6. Issue automatically appears in project (if auto-add is enabled)
7. Go to project and set custom fields

## Advanced: GitHub Actions Integration

For more advanced automation, you can use GitHub Actions to update project fields based on events.

**Example workflow:** Update project field when deployment succeeds

```yaml
name: Update Project on Deploy

on:
  deployment_status:

jobs:
  update-project:
    runs-on: ubuntu-latest
    steps:
      - name: Update project item
        uses: github/github-script@v7
        with:
          script: |
            # GraphQL mutation to update project field
            # (implementation details depend on project structure)
```

## Benefits of Using Projects

- ✅ **Single source of truth** - All work tracked in one place
- ✅ **Automatic syncing** - Issues and PRs update automatically
- ✅ **Multiple views** - See work from different perspectives
- ✅ **Learning tracking** - Document insights alongside implementation
- ✅ **Timeline planning** - Visualize practicum progress
- ✅ **Portfolio piece** - Demonstrates project management skills

## Resources

- [GitHub Projects Documentation](https://docs.github.com/en/issues/planning-and-tracking-with-projects)
- [GitHub Projects API](https://docs.github.com/en/graphql/reference/objects#projectv2)
- [Best Practices for Projects](https://github.blog/2023-01-19-5-tips-for-getting-started-with-github-projects/)

---

**Next Steps:**
1. Create your project using the instructions above
2. Set up the 5 recommended views
3. Add the custom fields
4. Enable automation workflows
5. Add your first few tasks
6. Start tracking your ML platform practicum journey!
