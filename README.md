# Redmine Merge Issues

A Redmine plugin that **merges issues**: moves all content from a source issue (comments, time entries, attachments, sub-issues, relations, watchers) into a destination issue, then deletes the source issue.

## Features

| Element | Behavior |
|---|---|
| **Source description** | Converted into a journal note in the destination issue |
| **Comments / journals** | Moved to the destination issue |
| **Time entries** | Moved to the destination issue |
| **Attachments** | Moved to the destination issue |
| **Sub-issues** | Re-parented to the destination issue |
| **Issue relations** | Moved (duplicates ignored, self-references avoided) |
| **Watchers** | Merged into the destination issue |
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

1. Open an issue (the source issue to be deleted)
2. Scroll to the bottom of the issue description — a **Merge** form is displayed there
3. Enter the destination issue number in the input field
4. Click **Merge**
5. The source issue is deleted and all its content is moved to the destination issue

## Compatibility

- Redmine ≥ 6.0
- Ruby ≥ 3.0

## Plugin Structure

```
redmine_merge_issues/
├── init.rb                                  # Plugin declaration
├── config/
│   ├── routes.rb                            # Routes: /issues/:issue_id/merge
│   └── locales/
│       ├── fr.yml                           # French translations
│       └── en.yml                           # English translations
├── app/
│   ├── controllers/
│   │   └── merge_issues_controller.rb       # Merge logic
│   ├── helpers/
│   │   └── merge_issues_helper.rb
│   └── views/
│       └── merge_issues/
│           └── _merge_link.html.erb         # Inline merge form (injected via hook)
└── lib/
    ├── redmine_merge_issues.rb
    └── redmine_merge_issues/
        └── hooks.rb                         # Redmine view hook
```