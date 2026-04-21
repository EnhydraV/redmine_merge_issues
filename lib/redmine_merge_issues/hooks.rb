# lib/redmine_merge_issues/hooks.rb
# frozen_string_literal: true

module RedmineMergeIssues
  class Hooks < Redmine::Hook::ViewListener
    # Injecte un <template> caché avec le lien Merge (vérif permission serveur).
    # Le JS merge_issues.js le déplace ensuite dans le menu "..." (.drdn-items).
    render_on :view_issues_show_description_bottom,
              partial: 'merge_issues/action_item'
  end
end
