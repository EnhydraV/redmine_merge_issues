require 'redmine'
# Force-load the hook class on plugin init so Redmine::Hook::ViewListener.inherited
# fires immediately. The original `Rails.application.config.to_prepare do
# require_dependency '...' end` pattern does NOT load the file under Rails 7 +
# Zeitwerk, leaving the hook unregistered (no merge button on the issue page).
require_relative 'lib/redmine_merge_issues/hooks'

Redmine::Plugin.register :redmine_merge_issues do
  name        'Merge Issues'
  author      'Vincent Vanwaelscappel'
  description 'Allows merging issues: moves all content from a source issue into a destination issue, then deletes the source.'
  version     '0.0.5'
  url         'https://github.com/EnhydraV/redmine_merge_issues'
  author_url  'https://github.com/EnhydraV'

  requires_redmine version_or_higher: '6.0'

  permission :merge_issues,
             { merge_issues: [:new, :create, :new_multiple, :create_multiple] }
end
