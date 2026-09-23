# Redmine Merge Issues

A Redmine plugin that **merges issues**: moves all content from a source issue (comments, time entries, attachments, sub-issues, relations, watchers) into a destination issue, then deletes the source issue.

## Features

| Element | Behavior |
|---|---|
| **Source description** | Converted into a journal note in the destination issue |
| **Comments / journals** | Moved to the destination issue |
| **Time entries** | Moved to the destination issue; when the merge crosses projects their project follows the destination, as Redmine does when an issue is moved |
| **Attachments** | Moved to the destination issue |
| **Sub-issues** | Re-parented to the destination issue through Redmine own nested set maintenance, so they keep showing up as sub-issues and the destination gets the usual *subtask added* journal entry |
| **Issue relations** | Moved to the destination. A relation Redmine would refuse there — linking the destination to itself, duplicating one it already has, linking it to one of its own ancestors or descendants, or crossing projects while cross-project relations are disabled — is dropped along with the source and logged |
| **Watchers** | Merged into the destination issue |
| **Custom field values** | Source values are snapshotted into a *private* journal note on the destination (they would otherwise be deleted with the source) |
| **Priority** | Escalated to the highest of source and destination |
| **Destination fields** | Unchanged (description, assignee, status, etc.) |
| **Merge note** | Automatically added as a journal note in the destination issue |

## Installation

```bash
# 1. Copy the plugin into Redmine's plugins folder
cp -r redmine_merge_issues /path/to/redmine/plugins/

# 2. Install dependencies (if needed)
cd /path/to/redmine
bundle install
```

## Permission Setup

1. Go to **Administration → Roles and permissions**
2. For each role that should be able to merge issues, check **"Merge issues"** under the *Issue tracking* section

## Usage

### From an issue page

1. Open an issue and pick **Merge** from the **"..."** actions dropdown
2. Enter the other issue number and choose the merge direction (which issue is kept)
3. Click **Merge** — the source issue is deleted and all its content is moved to the destination issue

### From the issue list

1. Select one or more issues in the issue list and open the context menu (right click)
2. Pick **Merge**:
   - with a single issue selected, the regular per-issue merge screen opens
   - with several issues selected, a screen asks which issue to **keep**; all the other selected issues are merged into it and then deleted
3. Click **Merge** to confirm

The context-menu entry is enabled only when the user has the *Merge issues* permission on the projects of all selected issues.

## Behavior and limits

- A merge runs in a single transaction: either everything moves or nothing does. When it cannot be completed, the message names the issue that caused the failure and no issue is deleted.
- Sub-issues are re-parented through the model, so a sub-issue that does not pass Redmine validations (a required custom field left empty by a past configuration change, for instance) aborts the merge instead of silently corrupting the issue tree. Fix the sub-issue, then merge again.
- Merging an issue into one of its own sub-issues is supported: the destination first takes the place of the source in the hierarchy, which is what keeps it from becoming its own parent.
- At most 50 issues can be merged in one go from the issue list. Each deletion takes Redmine global issue-tree lock, so an unbounded batch would hold it long enough to break concurrent issue updates.
- Merging across projects is allowed as long as the user holds the *Merge issues* permission on every project involved.

## Upgrading from 0.0.4 and earlier

Earlier versions moved sub-issues and relations with `update_columns`, which writes the
rows without going through Redmine. Merges already performed may therefore have left
data this version no longer produces:

- **Sub-issues of a merged issue** kept the nested set coordinates (`root_id`, `lft`,
  `rgt`) of the destroyed tree, so they no longer show up under the destination even
  though their `parent_id` points to it. `Issue.rebuild_tree!` recomputes those columns
  from `parent_id` and brings them back; it locks every issue, so run it from
  `bin/rails runner` during a maintenance window, on a backed up database.
- **Self-relations** (`#12 related to #12`) were created whenever the two merged issues
  were already related to each other. List them with
  `IssueRelation.where("issue_from_id = issue_to_id")` and delete them.

## Compatibility

- Redmine ≥ 6.0
- Ruby ≥ 3.0

## Plugin Structure

```
redmine_merge_issues/
├── init.rb                                  # Plugin declaration
├── config/
│   ├── routes.rb                            # Routes: /issues/:issue_id/merge and /issues/merge (multi)
│   └── locales/
│       ├── en.yml                           # English translations
│       ├── fr.yml                           # French translations
│       └── it.yml                           # Italian translations
├── app/
│   ├── controllers/
│   │   └── merge_issues_controller.rb       # Merge logic (single and multi-selection)
│   ├── helpers/
│   │   └── merge_issues_helper.rb
│   └── views/
│       └── merge_issues/
│           ├── _action_item.html.erb        # "Merge" link for the issue "..." menu (injected via hook)
│           ├── _context_menu.html.erb       # "Merge" entry for the issue-list context menu (hook)
│           ├── new.html.erb                 # Per-issue merge screen
│           └── new_multiple.html.erb        # Destination picker for multi-selection merge
├── assets/
│   └── javascripts/
│       └── merge_issues.js                  # Moves the merge link into the "..." dropdown
└── lib/
    ├── redmine_merge_issues.rb
    └── redmine_merge_issues/
        └── hooks.rb                         # Redmine view hooks
```