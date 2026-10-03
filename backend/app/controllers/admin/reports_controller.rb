module Admin
  class ReportsController < BaseController
    include AdminPagination

    # Decisions against the reported *person* (or the owner of what they reported).
    USER_DECISIONS = %w[warn suspend dismiss].freeze
    # Decisions against the reported *content* itself: each removes the content from public view
    # and auto-resolves every other open report on the same entity, since there is nothing left
    # for a second reviewer to act on.
    CONTENT_DECISIONS = %w[unpublish_job hide_review hide_act hide_portfolio hide_post hide_comment].freeze
    DECISIONS = (USER_DECISIONS + CONTENT_DECISIONS).freeze
    CONTENT_ENTITY_TYPE = { "unpublish_job" => "job", "hide_review" => "review", "hide_act" => "act", "hide_portfolio" => "portfolio",
      "hide_post" => "post", "hide_comment" => "comment" }.freeze
    STATUSES = %w[open resolved dismissed].freeze
    ENTITY_TYPES = %w[user job act review portfolio resume post comment].freeze
    EXCERPT_SIZE = 20
    HISTORY_WINDOW = 90.days
    NOTE_LIMIT = 1_000
    # Written by the conversation report flow at the end of `details` (after any text from the reporter).
    CONVERSATION_REFERENCE = /Reported from conversation (conv_[0-9a-f-]{36})\.?\s*\z/

    # Filters: status, entityType, reason. Pagination via the shared AdminPagination concern
    # (page/perPage/total; see backend/app/controllers/concerns/admin_pagination.rb).
    def index
      reports = Report.includes(:reporter).order(created_at: :desc)
      reports = reports.where(status: params[:status]) if STATUSES.include?(params[:status].to_s)
      reports = reports.where("lower(entity_type) = ?", params[:entityType].to_s.downcase) if ENTITY_TYPES.include?(params[:entityType].to_s.downcase)
      reports = reports.where(reason: params[:reason]) if params[:reason].present?

      rows, meta = admin_paginate(reports, default_per: 100)
      titles = entity_titles(rows)
      render json: { reports: rows.map { |r| r.attributes.merge(reporterName: r.reporter&.name, entityTitle: titles[[r.entity_type.to_s.downcase, r.entity_id]]) } }.merge(meta)
    end

    def update
      return render_error("Invalid report status.", :bad_request) unless %w[resolved dismissed].include?(params[:status])
      report = Report.find(params[:id]); report.update!(status: params[:status], resolved_by_id: current_user.id, resolved_at: Time.current); audit!("admin.report", report); render json: { ok: true }
    end

    # Everything a moderator needs to decide on one report: the reported user's history and, for a
    # report made from a conversation, the messages leading up to the report. Reading a private
    # conversation is audit-logged.
    def context
      report = Report.includes(:reporter).find(params[:id])
      target = target_user(report)
      conversation = reported_conversation(report, target)
      excerpt = conversation_excerpt(conversation, report)
      audit!("admin.report.context", report, conversationId: conversation&.id, messagesShown: excerpt ? excerpt[:messages].length : 0)
      render json: {
        report: serialize_report(report),
        reportedUser: target && { id: target.id, name: target.name, email: target.email, role: target.role, status: target.status, createdAt: target.created_at },
        history: target && history_for(target, report),
        conversation: excerpt,
        guidelinesUrl: "/community-guidelines"
      }
    end

    # Closes an open report with a recorded decision:
    #   warn         - the reported user gets an in-app notice pointing at the community guidelines
    #   suspend      - the reported user is suspended and signed out everywhere (as from the Users tab)
    #   dismiss      - no action against anyone
    #   unpublish_job/hide_review/hide_act/hide_portfolio - the reported content itself is taken down; every other
    #                  open report on that same entity is auto-resolved with the same decision
    def moderate
      decision = params[:decision]
      return render_error("Choose a valid moderation decision.", :bad_request, "INVALID_DECISION") unless decision.is_a?(String) && DECISIONS.include?(decision)
      note = params[:note]
      return render_error("note must be text.", :unprocessable_content, "INVALID_NOTE") unless note.nil? || note.is_a?(String)
      note = note.to_s.strip
      return render_error("The note can be at most #{NOTE_LIMIT} characters.", :unprocessable_content, "INVALID_NOTE") if note.length > NOTE_LIMIT

      report = Report.find(params[:id])
      return content_moderate(report, decision, note) if CONTENT_DECISIONS.include?(decision)

      target = target_user(report)
      if decision != "dismiss"
        return render_error("This report is not about a person or their listing, so there is nobody to #{decision}.", :unprocessable_content, "NO_TARGET") unless target
        return render_error("You cannot #{decision} yourself.", :conflict, "SELF_TARGET") if target.id == current_user.id
        return render_error("Admins cannot be #{decision == 'warn' ? 'warned' : 'suspended'} from a report.", :conflict, "ADMIN_TARGET") if target.admin?
        return render_error("This account was deleted by its owner.", :conflict, "ACCOUNT_DELETED") if target.deleted?
      end

      revoked = nil
      Report.transaction do
        report.lock!
        unless report.status == "open"
          render_error("This report was already closed.", :conflict, "REPORT_CLOSED")
          raise ActiveRecord::Rollback
        end
        case decision
        when "warn"
          Notifier.moderation_warning(target, note.presence)
        when "suspend"
          target.update!(status: "suspended")
          revoked = Session.revoke!(target.sessions)
          audit!("admin.user.status", target, status: target.status, reportId: report.id)
        end
        report.update!(status: decision == "dismiss" ? "dismissed" : "resolved", action_taken: decision, resolution_note: note.presence,
          resolved_by_id: current_user.id, resolved_at: Time.current)
        audit!("admin.report.#{decision}", report, targetUserId: target&.id, sessionsRevoked: revoked, note: note.presence)
      end
      return if performed?

      render json: { ok: true, report: serialize_report(report) }
    end

    private

    # Removes the reported content itself (job/review/act) and auto-resolves every other open
    # report already filed against that same entity, since a second reviewer would find nothing
    # left to act on.
    def content_moderate(report, decision, note)
      expected_type = CONTENT_ENTITY_TYPE.fetch(decision)
      entity_type = report.entity_type.to_s.downcase
      return render_error("This action only applies to a #{expected_type} report.", :unprocessable_content, "WRONG_ENTITY_TYPE") unless entity_type == expected_type

      entity = content_entity(expected_type, report.entity_id)
      return render_error("This #{expected_type} no longer exists.", :not_found, "ENTITY_NOT_FOUND") unless entity

      resolved = []
      Report.transaction do
        report.lock!
        unless report.status == "open"
          render_error("This report was already closed.", :conflict, "REPORT_CLOSED")
          raise ActiveRecord::Rollback
        end
        case decision
        when "unpublish_job" then entity.update!(status: "rejected", moderation_note: "Removed after a safety report")
        when "hide_review" then entity.update!(status: "rejected")
        when "hide_act" then entity.update!(status: "hidden")
        when "hide_portfolio" then entity.update!(status: "hidden")
        when "hide_post" then entity.update!(status: "hidden")
        when "hide_comment" then entity.update!(status: "hidden")
        end
        audit!("admin.report.#{decision}", report, entityType: expected_type, entityId: entity.id)

        open_reports = Report.where(entity_id: report.entity_id).where("lower(entity_type) = ?", expected_type).where(status: "open").lock
        resolved = open_reports.to_a
        resolved.each do |r|
          r.update!(status: "resolved", action_taken: decision, resolution_note: note.presence, resolved_by_id: current_user.id, resolved_at: Time.current)
          audit!("admin.report.auto_resolved", r, decision: decision) unless r.id == report.id
        end
      end
      return if performed?

      render json: { ok: true, report: serialize_report(report.reload), resolvedReportIds: resolved.map(&:id) }
    end

    def content_entity(entity_type, entity_id)
      case entity_type
      when "job" then Job.find_by(id: entity_id)
      when "review" then Review.find_by(id: entity_id)
      when "act" then Act.find_by(id: entity_id)
      when "portfolio" then Portfolio.find_by(id: entity_id)
      when "post" then Post.find_by(id: entity_id)
      when "comment" then PostComment.find_by(id: entity_id)
      end
    end

    # The account a report is about: the user itself, or the owner of the reported listing.
    def target_user(report)
      case report.entity_type.to_s.downcase
      when "user" then User.find_by(id: report.entity_id)
      when "job" then Job.find_by(id: report.entity_id)&.employer
      when "act" then Act.find_by(id: report.entity_id)&.owner
      when "portfolio" then portfolio_owner_user(Portfolio.find_by(id: report.entity_id))
      when "resume" then Resume.find_by(id: report.entity_id)&.user
      end
    end

    # The person answerable for a portfolio: its owner, or the owner of the Page that owns it.
    def portfolio_owner_user(portfolio)
      owner = portfolio&.owner
      case owner
      when User then owner
      when Organization, Act then owner.owner
      end
    end

    # Only a conversation between the reporter and the reported user: the reporter controls the
    # details text, so an id pointing at someone else's conversation is ignored.
    def reported_conversation(report, target)
      return nil unless target && report.reporter_id && report.entity_type.to_s.downcase == "user"
      id = report.details.to_s[CONVERSATION_REFERENCE, 1]
      conversation = id && Conversation.find_by(id:)
      return nil unless conversation
      participants = [conversation.candidate_id, conversation.employer_id]
      participants.sort == [report.reporter_id, target.id].sort ? conversation : nil
    end

    def conversation_excerpt(conversation, report)
      return nil unless conversation
      before = conversation.messages.includes(:sender).where(created_at: ..report.created_at)
        .order(created_at: :desc, id: :desc).limit(EXCERPT_SIZE).to_a.reverse
      {
        id: conversation.id, jobTitle: conversation.job&.title,
        participants: [conversation.candidate, conversation.employer].map { { id: _1.id, name: _1.name } },
        messages: before.map { { id: _1.id, senderId: _1.sender_id, senderName: _1.sender.name, body: _1.body, createdAt: _1.created_at, safetyFlags: _1.safety_flags } },
        earlierMessages: [conversation.messages.where(created_at: ..report.created_at).count - before.length, 0].max,
        laterMessages: conversation.messages.where("created_at > ?", report.created_at).count
      }
    end

    def history_for(user, report)
      about = reports_about(user)
      {
        reportsTotal: about.count,
        reportsLast90Days: about.where(created_at: HISTORY_WINDOW.ago..).count,
        openReports: about.where(status: "open").where.not(id: report.id).count,
        warnings: about.where(action_taken: "warn").count,
        suspensions: about.where(action_taken: "suspend").count,
        flaggedMessagesLast90Days: Message.flagged.where(sender_id: user.id, created_at: HISTORY_WINDOW.ago..).count
      }
    end

    def reports_about(user)
      Report.where(entity_type: %w[user User], entity_id: user.id)
        .or(Report.where(entity_type: %w[job Job], entity_id: Job.where(employer_id: user.id).select(:id)))
        .or(Report.where(entity_type: %w[act Act], entity_id: Act.where(owner_id: user.id).select(:id)))
        .or(Report.where(entity_type: "portfolio", entity_id: Portfolio.where(owner_type: "user", owner_id: user.id).select(:id)))
        .or(Report.where(entity_type: "resume", entity_id: Resume.where(user_id: user.id).select(:id)))
    end

    # A short label per (entity_type, entity_id) so the reports list can show what was reported
    # without a query per row.
    def entity_titles(reports)
      by_type = reports.group_by { _1.entity_type.to_s.downcase }
      ids_for = ->(type) { (by_type[type] || []).map(&:entity_id) }
      titles = {}
      User.where(id: ids_for.call("user")).pluck(:id, :name).each { |id, name| titles[["user", id]] = name }
      Job.where(id: ids_for.call("job")).pluck(:id, :title).each { |id, title| titles[["job", id]] = title }
      Act.where(id: ids_for.call("act")).pluck(:id, :name).each { |id, name| titles[["act", id]] = name }
      Portfolio.where(id: ids_for.call("portfolio")).pluck(:id, :title).each { |id, title| titles[["portfolio", id]] = title }
      Resume.where(id: ids_for.call("resume")).pluck(:id, :title).each { |id, title| titles[["resume", id]] = title }
      Review.where(id: ids_for.call("review")).pluck(:id, :title).each { |id, title| titles[["review", id]] = title.presence || "Review" }
      Post.where(id: ids_for.call("post")).find_each { |post| titles[["post", post.id]] = post.body.to_s.truncate(60).presence || "Post" }
      PostComment.where(id: ids_for.call("comment")).find_each { |comment| titles[["comment", comment.id]] = comment.body.to_s.truncate(60) }
      titles
    end

    def serialize_report(report)
      { id: report.id, entityType: report.entity_type, entityId: report.entity_id, reason: report.reason, details: report.details,
        status: report.status, actionTaken: report.action_taken, resolutionNote: report.resolution_note, createdAt: report.created_at,
        resolvedAt: report.resolved_at, reporterId: report.reporter_id, reporterName: report.reporter&.name }
    end
  end
end
