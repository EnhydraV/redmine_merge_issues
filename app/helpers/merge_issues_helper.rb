# frozen_string_literal: true

module MergeTicketsHelper
  # Returns true if the current user can merge issues in the given project
  def can_merge_issues?(project)
    User.current.allowed_to?(:merge_issues, project)
  end
end
