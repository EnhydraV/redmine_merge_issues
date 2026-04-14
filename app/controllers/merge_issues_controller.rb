# frozen_string_literal: true

class MergeIssuesController < ApplicationController
  before_action :find_issue
  before_action :authorize

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
    destination_id = params[:destination_issue_id].to_s.gsub(/\A#/, '').strip.to_i

    if destination_id == @issue.id
      return redirect_back_with_error(l(:error_merge_same_issue))
    end

    @destination = Issue.find_by(id: destination_id)

    unless @destination
      return redirect_back_with_error(l(:error_merge_destination_not_found))
    end

    unless User.current.allowed_to?(:merge_issues, @destination.project)
      return redirect_back_with_error(l(:error_merge_not_allowed_on_destination))
    end

    begin
      ActiveRecord::Base.transaction do
        merge_issues!(@issue, @destination)
      end
      flash[:notice] = l(:notice_merge_success, source: @issue.id, destination: @destination.id)
      redirect_to issue_path(@destination)
    rescue StandardError => e
      redirect_back_with_error(l(:error_merge_failed, message: e.message))
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

  def redirect_back_with_error(message)
    flash[:error] = message
    redirect_to issue_path(@issue)
  end

  # ---------------------------------------------------------------
  # Core merge logic
  # ---------------------------------------------------------------
  def merge_issues!(source, destination)
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

    # 2. Move journals (comments) from source → destination
    source.journals.each do |journal|
      journal.update_columns(journalized_id: destination.id)
    end

    # 3. Move time entries
    source.time_entries.each do |entry|
      entry.update_columns(issue_id: destination.id)
    end

    # 4. Move attachments
    source.attachments.each do |attachment|
      attachment.update_columns(container_id: destination.id)
    end

    # 5. Move child issues (sub-tickets)
    source.children.each do |child|
      child.update_columns(parent_id: destination.id)
    end

    # 6. Move issue relations (avoid duplicates and self-relations)
    source.relations.each do |relation|
      other_id   = (relation.issue_from_id == source.id) ? relation.issue_to_id   : relation.issue_from_id
      other_side = (relation.issue_from_id == source.id) ? :issue_from_id          : :issue_to_id

      # Skip if the relation would become self-referential or already exists
      next if other_id == destination.id
      existing = IssueRelation.where(
        issue_from_id: [destination.id, other_id],
        issue_to_id:   [destination.id, other_id]
      ).where(relation_type: relation.relation_type).exists?
      next if existing

      relation.update_columns(other_side => destination.id)
    end

    # 7. Update any relations that still reference source (from_id or to_id)
    IssueRelation.where(issue_from_id: source.id).update_all(issue_from_id: destination.id)
    IssueRelation.where(issue_to_id:   source.id).update_all(issue_to_id:   destination.id)

    # 8. Move watchers
    source.watcher_users.each do |user|
      destination.add_watcher(user) unless destination.watched_by?(user)
    end

    # 9. Add a journal note to destination referencing the merge
    merge_note = l(:label_merge_note, source_id: source.id, source_subject: source.subject,
                                      user: User.current.name, date: format_date(Date.today))
    journal = destination.init_journal(User.current, merge_note)
    journal.notify = false
    destination.save!

    # 10. Destroy source issue (skips callbacks that might be slow; adjust if needed)
    source.destroy
  end
end
