require 'redmine'

Rails.application.config.to_prepare do
  require_dependency 'redmine_merge_issues/hooks'
end

Redmine::Plugin.register :redmine_merge_issues do
  name        'Merge Issues'
  author      'Vincent Vanwaelscappel'
  description 'Allows merging issues: moves all content from a source issue into a destination issue, then deletes the source.'
  version     '0.0.1'
  url         'https://github.com/EnhydraV/redmine_merge_issues'
  author_url  'https://github.com/EnhydraV'

  requires_redmine version_or_higher: '6.0'

  permission :merge_issues,
             { merge_issues: [:new, :create] }
end
