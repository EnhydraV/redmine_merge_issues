require 'redmine'

Redmine::Plugin.register :redmine_merge_issues do
  name        'Redmine Merge Issues'
  author      'Plugin Author'
  description 'Allows merging issues: moves all content from a source issue into a destination issue, then deletes the source.'
  version     '1.0.0'
  url         'https://github.com/EnhydraV/redmine_merge_issues'
  author_url  'https://github.com/EnhydraV'

  requires_redmine version_or_higher: '5.0'

  permission :merge_issues,
             { merge_issues: [:new, :create] },
             require: :member
end
