# frozen_string_literal: true

class MergeIssuesController < ApplicationController
  # Raised when a merge has to be given up. Its message is user facing and
  # names the issue that could not be merged: a multiple merge runs in a single
  # transaction, so one failing source rolls the whole batch back and the user
  # needs to know which one it was.
  class MergeError < StandardError; end

  # Upper bound for a multiple merge. Every source is destroyed inside the
  # single wrapping transaction and each destroy takes Redmine's global
  # `lock_issues` advisory lock, which times out after 30s (see
  # Redmine::NestedSet::IssueNestedSet#lock_nested_set), so an unbounded
  # selection would sit on that lock long enough to break concurrent issue
  # updates.
  MAX_SELECTED_ISSUES = 50

  # `helper :custom_fields` makes `show_value` available on view_context, which
  # is used by snapshot_source_custom_values below. Redmine's ApplicationController
  # does NOT do `helper :all`, so each controller must include the helpers it needs.
  helper :custom_fields

  before_action :find_issue, only: [:new, :create]
  before_action :authorize, only: [:new, :create]
  before_action :find_selected_issues, only: [:new_multiple, :create_multiple]
  before_action :authorize_selected_issues, only: [:new_multiple, :create_multiple]

  # GET /issues/:issue_id/merge/new
  # Renders the merge modal (used via Turbo or plain AJAX)
  def new
    respond_to do |format|
      format.html
      format.js
    end
  end

  # POST /issues/:issue_id/merge
  def create
    other_id = params[:other_issue_id].to_s.gsub(/\A#/, '').strip.to_i

    if other_id == 0 || other_id == @issue.id
      return redirect_back_with_error(l(:error_merge_same_issue))
    end

    other = Issue.visible.find_by(id: other_id)

    unless other
      return redirect_back_with_error(l(:error_merge_other_not_found))
    end

    # Détermine source (supprimée) et destination (conservée) selon le sens choisi.
    # 'from_other' : la demande saisie est la source, la demande courante la destination.
    # Sinon (défaut) : la demande courante est la source, la demande saisie la destination.
    if params[:merge_direction].to_s == 'from_other'
      source = other
      destination = @issue
    else
      source = @issue
      destination = other
    end

    # Les deux projets sont impactés : on exige la permission sur chacun.
    unless User.current.allowed_to?(:merge_issues, source.project) &&
           User.current.allowed_to?(:merge_issues, destination.project)
      return redirect_back_with_error(l(:error_merge_not_allowed_on_destination))
    end

    begin
      ActiveRecord::Base.transaction do
        merge_issues_with_error_context!(source, destination)
      end
      flash[:notice] = l(:notice_merge_success, source: source.id, destination: destination.id)
      redirect_to issue_path(destination)
    rescue MergeError => e
      Rails.logger.error("[MergeIssues] Merge failed: #{e.message}")
      redirect_back_with_error(e.message)
    rescue StandardError => e
      Rails.logger.error("[MergeIssues] Merge failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      redirect_back_with_error(l(:error_merge_failed))
    end
  end

  # GET /issues/merge/new?ids[]=1&ids[]=2
  # Lets the user pick which of the selected issues to keep (destination)
  def new_multiple
  end

  # POST /issues/merge
  # Merges every selected issue except the destination into the destination,
  # deleting each source issue.
  def create_multiple
    destination = @issues.detect { |issue| issue.id == params[:destination_id].to_i }

    unless destination
      return redirect_to_selection_with_error(l(:error_merge_destination_not_found))
    end

    sources = @issues - [destination]

    begin
      ActiveRecord::Base.transaction do
        sources.each { |source| merge_issues_with_error_context!(source, destination) }
      end
      flash[:notice] = l(:notice_merge_multiple_success,
                         sources: sources.map { |s| "##{s.id}" }.join(', '),
                         destination: destination.id)
      redirect_to issue_path(destination)
    rescue MergeError => e
      Rails.logger.error("[MergeIssues] Multiple merge failed: #{e.message}")
      redirect_to_selection_with_error(e.message)
    rescue StandardError => e
      Rails.logger.error("[MergeIssues] Multiple merge failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      redirect_to_selection_with_error(l(:error_merge_failed))
    end
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize
    unless User.current.allowed_to?(:merge_issues, @issue.project)
      deny_access
    end
  end

  # Loads the issues selected from the issue list (ids[] param).
  #
  # params[:ids] is whatever the query string holds, not necessarily an array
  # of numbers, so anything that is not an id is dropped rather than blown up
  # on: `Array(params[:ids]).map(&:to_i)` raises NoMethodError (500) on
  # `?ids[a]=1`. 404 unless every requested issue is readable and at least two
  # of them were requested; a selection that went stale (the screen submitted
  # again after the merge already happened) is not distinguishable from a
  # tampered one, and Redmine answers 404 for both in ApplicationController#find_issues.
  def find_selected_issues
    ids = Array.wrap(params[:ids]).
            flat_map { |value| value.to_s.split(',') }.
            filter_map { |value| value[/\A\s*(\d+)\s*\z/, 1]&.to_i }.
            uniq

    if ids.size > MAX_SELECTED_ISSUES
      return render_error(message: l(:error_merge_too_many_issues, max: MAX_SELECTED_ISSUES),
                          status: 422)
    end

    @issues = Issue.visible.preload(:project).where(id: ids).sort_by(&:id)
    return render_404 if @issues.size < 2 || @issues.size != ids.size

    # Where the issue list was left. The context menu passes it along so that
    # Back and Cancel return to the filtered list instead of the global one.
    @back_url = validate_back_url(params[:back_url].to_s) || issues_path
  end

  # All impacted projects require the merge permission.
  def authorize_selected_issues
    unless @issues.map(&:project).uniq.all? { |project| User.current.allowed_to?(:merge_issues, project) }
      deny_access
    end
  end

  def redirect_back_with_error(message)
    flash[:error] = message
    redirect_to issue_path(@issue)
  end

  def redirect_to_selection_with_error(message)
    flash[:error] = message
    redirect_to new_merge_issues_path(ids: @issues.map(&:id), back_url: @back_url)
  end

  # ---------------------------------------------------------------
  # Core merge logic
  # ---------------------------------------------------------------

  # Runs the merge, turning the validation failures raised from deep inside
  # Redmine's models into a message naming the source that could not be merged.
  def merge_issues_with_error_context!(source, destination)
    merge_issues!(source, destination)
  rescue MergeError
    raise
  rescue ActiveRecord::RecordInvalid => e
    raise MergeError, l(:error_merge_issue_failed,
                        id: source.id,
                        message: e.record.errors.full_messages.join(', '))
  end

  def merge_issues!(source, destination)
    # Both issues were loaded before the merge started and the destination is
    # reused for every source of a multiple merge. Destroying an issue shifts
    # the nested set columns of its whole tree and a merge re-parents issues,
    # so work from fresh values. clear_journal drops the journal left over from
    # the previous source, which Journal#save would otherwise re-open and fill
    # with unrelated details.
    source.reload
    destination.reload
    destination.clear_journal

    # 1. Convert source description to a journal note in destination
    if source.description.present?
      author = source.author || User.current
      note_text = <<~NOTE
        #{l(:label_merge_original_description, id: source.id, subject: source.subject)}

        #{source.description}
      NOTE
      journal = Journal.new(journalized: destination, user: author, notes: note_text)
      journal.notify = false
      journal.save!
      journal.update_column(:created_on, source.created_on)
    end

    # 2. Move journals (comments), time entries and attachments to destination.
    #
    # These go through the class and not through source.journals & co on
    # purpose: loading an association and then moving its rows behind its back
    # leaves the moved records in the association cache, and `dependent:
    # :destroy` destroys that *cached* target
    # (ActiveRecord::Associations::HasManyAssociation#handle_dependency), not
    # what the database still holds. It only survived because Redmine's
    # before_destroy :destroy_children happens to call reload first, which
    # empties the cache — nothing to rely on.
    Journal.where(journalized_type: 'Issue', journalized_id: source.id).
      update_all(journalized_id: destination.id)

    # A time entry carries its own project_id next to issue_id;
    # Issue#after_project_change keeps the two in sync when an issue changes
    # project, and a merge across projects is such a move. Leaving project_id
    # behind books the hours on the wrong project and makes the entry invalid
    # (TimeEntry#validate_time_entry rejects project != issue.project).
    TimeEntry.where(issue_id: source.id).
      update_all(issue_id: destination.id, project_id: destination.project_id)

    Attachment.where(container_type: 'Issue', container_id: source.id).
      update_all(container_id: destination.id)

    # 3. Move sub-issues and issue relations
    move_children!(source, destination)
    move_relations!(source, destination)

    # 4. Move changesets (repository revisions)
    new_changesets = source.changesets - destination.changesets
    destination.changesets << new_changesets if new_changesets.any?
    source.changesets.clear

    # 5. Move watchers
    # On crée les Watcher directement (au lieu de add_watcher qui utilise
    # Watcher.create sans bang et avale les erreurs de validation silencieusement).
    # Toute copie échouée est tracée dans les logs au lieu de disparaître.
    existing_watcher_ids = destination.watcher_user_ids
    source.watcher_users.each do |user|
      next if existing_watcher_ids.include?(user.id)

      watcher = Watcher.new(watchable: destination, user: user)
      if watcher.save
        existing_watcher_ids << user.id
      else
        Rails.logger.warn(
          "[MergeIssues] Watcher non copié (issue ##{source.id} -> ##{destination.id}) " \
          "user ##{user.id} (#{user.login}) : #{watcher.errors.full_messages.join(', ')}"
        )
      end
    end
    destination.watchers.reload

    # 6. Escalate priority to the highest of source and destination
    if source.priority.position > destination.priority.position
      destination.priority = source.priority
    end

    # 7. Add a journal note to destination referencing the merge.
    # init_journal is a `||=`: it would return an already opened journal
    # without applying the note, which is why nothing between the
    # clear_journal above and this point may open one on the destination.
    merge_note = l(:label_merge_note, source_id: source.id, source_subject: source.subject,
                                      user: User.current.name, date: format_date(Date.today))
    journal = destination.init_journal(User.current, merge_note)
    journal.notify = false
    destination.save!

    # 7bis. Snapshot the source's custom field values as a *private* journal note
    # on the destination. acts_as_customizable declares custom_values with
    # `dependent: :delete_all`, so step 8 hard-deletes them — without this
    # snapshot the values would be lost. The note is private so the data is
    # available to users with `view_private_notes` permission only.
    snapshot_source_custom_values(source, destination)

    # 8. Destroy source issue. destroy! and not destroy: a callback vetoing the
    # deletion would otherwise be swallowed and the transaction would commit,
    # leaving an emptied duplicate of the issue behind.
    source.destroy!
  end

  # Re-parents the sub-issues of the source onto the destination.
  #
  # `update_columns(parent_id: …)` is not an option: it leaves root_id/lft/rgt
  # untouched, so the sub-issues keep the coordinates of the source's tree, are
  # shifted into negative values when the source is destroyed
  # (Redmine::NestedSet::IssueNestedSet#destroy_children) and then never show
  # up under the destination, whose sub-issue list is built from the nested set
  # and not from parent_id. Going through parent_issue_id= + save runs
  # Redmine's own nested set maintenance, its parent validations and the
  # "subtask added/removed" journal entries.
  def move_children!(source, destination)
    # Merging an issue into one of its own descendants would hand the
    # destination a subtree it belongs to: the destination would become its own
    # parent, or part of a parent/child cycle (Issue#soonest_start walks
    # parents and would recurse until the stack blows). The destination takes
    # the place of the source in the hierarchy first, which pulls it out of the
    # subtree that is about to move.
    if ancestor_ids_of(destination).include?(source.id)
      update_parent!(destination, source.parent_id)
    end

    source.children.each do |child|
      update_parent!(child, destination.id)
    end
  end

  # Ids of the ancestors of `issue`, walked through parent_id with fresh reads.
  # lft/rgt are deliberately not used: a previous source of the same multiple
  # merge may have shifted them without the objects in memory knowing. The
  # `include?` guard keeps a pre-existing cycle in the data from looping here.
  def ancestor_ids_of(issue)
    ids = []
    current_id = Issue.where(id: issue.id).pick(:parent_id)
    while current_id && !ids.include?(current_id)
      ids << current_id
      current_id = Issue.where(id: current_id).pick(:parent_id)
    end
    ids
  end

  def update_parent!(issue, parent_id)
    issue.parent_issue_id = parent_id
    return if issue.save

    raise MergeError, l(:error_merge_parent_update_failed,
                        id: issue.id,
                        message: issue.errors.full_messages.join(', '))
  end

  # Moves the relations of the source onto the destination.
  #
  # Saving through the model is what enforces Redmine's own rules: a relation
  # is not moved when it would link the destination to itself, duplicate a
  # relation the destination already has (issue_relations carries a unique
  # index on issue_from_id/issue_to_id), link the destination to one of its
  # ancestors or descendants, or cross projects while
  # cross_project_issue_relations is off. Such a relation is left on the source
  # and goes away with it, since Issue declares relations_from and relations_to
  # as `dependent: :delete_all`.
  def move_relations!(source, destination)
    source.relations.each do |relation|
      side = relation.issue_from_id == source.id ? :issue_from_id : :issue_to_id
      relation.public_send(:"#{side}=", destination.id)
      next if relation.save

      Rails.logger.info(
        "[MergeIssues] Relation ##{relation.id} not moved (issue ##{source.id} -> ##{destination.id}) : " \
        "#{relation.errors.full_messages.join(', ')}"
      )
    end
  end

  # Builds a private journal note on `destination` containing each non-blank
  # custom field value from `source`, formatted with the same helper Redmine
  # uses on the issue page (so enumeration / user / version values are shown by
  # name, not by id). Skipped when the source has no non-blank values.
  def snapshot_source_custom_values(source, destination)
    cfvs = source.visible_custom_field_values.reject { |cfv| cfv.value.blank? }
    return if cfvs.empty?

    body_lines = cfvs.map do |cfv|
      "**#{cfv.custom_field.name}**\n#{view_context.show_value(cfv, false)}"
    end

    note_body = "#{l(:label_merge_source_custom_fields_heading, id: source.id)}\n\n" \
                "#{body_lines.join("\n\n")}"

    journal = Journal.new(
      journalized: destination,
      user: User.current,
      notes: note_body,
      private_notes: true
    )
    journal.notify = false
    journal.save!
  end
end
