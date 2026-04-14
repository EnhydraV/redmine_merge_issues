# lib/redmine_merge_issues/hooks.rb
# frozen_string_literal: true

module RedmineMergeIssues
  class Hooks < Redhat::Hook::ViewListener
    # Inject a "Merge" link in the issue detail toolbar
    # (right next to "Copy" and "Edit" at the top of the issue page)
    render_on :view_issues_show_details_bottom,
              partial: 'merge_issues/merge_link'
  end
end
