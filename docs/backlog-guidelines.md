# Writing backlog tasks by hand

Tasks are Markdown files written by hand; the Backlog.md CLI isn't installed. `backlog/` is
gitignored on purpose, so task files are never committed.

## Where tasks go

- Tasks: `backlog/tasks/task-<id> - <Title-with-hyphens>.md`, using the next unused id.
- Unconfirmed ideas: `backlog/drafts/draft-<id> - <Title-with-hyphens>.md`.

## Template

```markdown
---
id: task-42
title: Short summary of the task
status: To Do
assignee: []
created_date: 'YYYY-MM-DD'
labels: []
dependencies: []
---

## Description

Why this task exists and what it achieves. No implementation details.

## Acceptance Criteria

- [ ] An outcome someone can check

## Implementation Plan

Added when work starts, not when the task is written.

## Implementation Notes

Added when work finishes: approach, decisions, deviations from the plan, files changed.
```

`status` is `To Do`, `In Progress` or `Done`.

## Acceptance criteria

Describe outcomes and behavior, not steps.

- Good: `- [ ] The stations list appears on a cold start with no network.`
- Bad: `- [ ] Add a new function in DataManager.`

Keep each task small enough for one PR, and only depend on tasks that already exist. If the work
needs something outside the criteria, update the criteria first or write a new task.

## Definition of done

Mark a task `Done` only when:

1. Every acceptance criterion is checked (`- [x]`).
2. New logic has tests, and the tests pass.
3. UI changes have been tried on a device or simulator, or Joe has done so.
4. `## Implementation Notes` is filled in, and any affected docs are updated.
