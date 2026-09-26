module SyntheticQa
  class BatchCleanup
    Result = Data.define(:batch, :users_removed, :records_removed)

    def self.call(...) = new(...).call

    # authorized_by: an active admin may purge demo-* batches in any environment (admin demo-data UI).
    def initialize(batch:, authorized_by: nil)
      @batch = batch.to_s
      @authorized_by = authorized_by
      @counts = Hash.new(0)
    end

    def call
      guard!
      user_ids = User.synthetic(batch).pluck(:id)
      return Result.new(batch:, users_removed: 0, records_removed: 0) if user_ids.empty?

      ApplicationRecord.transaction do
        ids = collect_ids(user_ids)
        delete_relational_rows(user_ids, ids)
        delete_owned_rows(user_ids, ids)
        delete_user_rows(user_ids)
      end

      Result.new(batch:, users_removed: @counts.fetch("users", 0), records_removed: @counts.values.sum)
    end

    private

    attr_reader :batch, :authorized_by

    def guard!
      raise ArgumentError, "Invalid synthetic batch." unless batch.match?(/\A[a-z0-9][a-z0-9-]{2,63}\z/)
      if authorized_by
        raise SecurityError, "Only an active admin can delete demo data." unless authorized_by.admin? && authorized_by.active?
        raise ArgumentError, "Only demo-* batches can be deleted from the admin UI." unless Demo.batch?(batch)
      elsif !(Rails.env.test? || Rails.env.development? || ENV["ALLOW_SYNTHETIC_QA"] == "true")
        raise SecurityError, "Synthetic QA cleanup is disabled. Set ALLOW_SYNTHETIC_QA=true for an explicitly approved environment."
      end
    end

    def collect_ids(user_ids)
      job_ids = Job.where(employer_id: user_ids).pluck(:id)
      application_ids = Application.where(job_id: job_ids).or(Application.where(candidate_id: user_ids)).pluck(:id)
      act_ids = Act.where(owner_id: user_ids).pluck(:id)
      booking_ids = BookingRequest.where(act_id: act_ids).or(BookingRequest.where(requester_id: user_ids)).pluck(:id)
      quote_ids = BookingQuote.where(booking_request_id: booking_ids).or(BookingQuote.where(created_by_id: user_ids)).pluck(:id)
      conversation_ids = Conversation.where(candidate_id: user_ids).or(Conversation.where(employer_id: user_ids)).or(Conversation.where(job_id: job_ids)).pluck(:id)
      organization_ids = Organization.where(owner_id: user_ids).pluck(:id)
      urgent_request_ids = UrgentRequest.where(requester_id: user_ids).pluck(:id)
      folder_ids = TalentFolder.where(owner_id: user_ids).pluck(:id)
      band_project_ids = BandProject.where(owner_id: user_ids).pluck(:id)
      crew_plan_ids = CrewPlan.where(owner_id: user_ids).pluck(:id)
      alert_ids = JobAlert.where(user_id: user_ids).pluck(:id)
      notification_ids = Notification.where(user_id: user_ids).pluck(:id)
      portfolio_ids = PortfolioItem.where(user_id: user_ids).pluck(:id)

      values = {
        jobs: job_ids, applications: application_ids, acts: act_ids, bookings: booking_ids, quotes: quote_ids,
        conversations: conversation_ids, organizations: organization_ids, urgent_requests: urgent_request_ids,
        folders: folder_ids, band_projects: band_project_ids, crew_plans: crew_plan_ids, alerts: alert_ids,
        notifications: notification_ids, portfolios: portfolio_ids
      }
      values[:all_entity_ids] = (user_ids + values.values.flatten).uniq
      values
    end

    def delete_relational_rows(user_ids, ids)
      remove(JobAlertDelivery.where(job_alert_id: ids[:alerts]).or(JobAlertDelivery.where(job_id: ids[:jobs])).or(JobAlertDelivery.where(notification_id: ids[:notifications])), "job_alert_deliveries")
      remove(ApplicationEvent.where(application_id: ids[:applications]).or(ApplicationEvent.where(actor_id: user_ids)), "application_events")
      remove(Message.where(conversation_id: ids[:conversations]).or(Message.where(sender_id: user_ids)), "messages")
      remove(BookingPayment.where(booking_request_id: ids[:bookings]).or(BookingPayment.where(booking_quote_id: ids[:quotes])).or(BookingPayment.where(payer_id: user_ids)), "booking_payments")
      remove(BookingQuote.where(id: ids[:quotes]), "booking_quotes")
      remove(ActMember.where(act_id: ids[:acts]).or(ActMember.where(user_id: user_ids)), "act_members")
      remove(OrganizationMember.where(organization_id: ids[:organizations]).or(OrganizationMember.where(user_id: user_ids)), "organization_members")
      remove(UrgentRequestResponse.where(urgent_request_id: ids[:urgent_requests]).or(UrgentRequestResponse.where(user_id: user_ids)), "urgent_request_responses")
      remove(TalentFolderMember.where(talent_folder_id: ids[:folders]).or(TalentFolderMember.where(candidate_id: user_ids)), "talent_folder_members")
      remove(TalentShortlist.where(employer_id: user_ids).or(TalentShortlist.where(candidate_id: user_ids)), "talent_shortlists")
      remove(SavedJob.where(user_id: user_ids).or(SavedJob.where(job_id: ids[:jobs])), "saved_jobs")
      remove(BandProjectRole.where(band_project_id: ids[:band_projects]).or(BandProjectRole.where(opportunity_id: ids[:jobs])), "band_project_roles")
      remove(CrewPlanRole.where(crew_plan_id: ids[:crew_plans]), "crew_plan_roles")
    end

    def delete_owned_rows(user_ids, ids)
      remove(BookingRequest.where(id: ids[:bookings]), "booking_requests")
      remove(Conversation.where(id: ids[:conversations]), "conversations")
      remove(Application.where(id: ids[:applications]), "applications")
      remove(Report.where(reporter_id: user_ids).or(Report.where(resolved_by_id: user_ids)).or(Report.where(entity_id: ids[:all_entity_ids])), "reports")
      remove(Review.where(author_id: user_ids).or(Review.where(employer_id: user_ids)), "reviews")
      remove(VerificationRequest.where(user_id: user_ids).or(VerificationRequest.where(reviewed_by_id: user_ids)), "verification_requests")
      remove(AuditLog.where(actor_id: user_ids).or(AuditLog.where(entity_id: ids[:all_entity_ids])), "audit_logs")
      remove(BillingEvent.where(user_id: user_ids), "billing_events")
      remove(BillingAttempt.where(user_id: user_ids), "billing_attempts")
      remove(Job.where(id: ids[:jobs]), "jobs")
      remove(Act.where(id: ids[:acts]), "acts")
      remove(Organization.where(id: ids[:organizations]), "organizations")
      remove(UrgentRequest.where(id: ids[:urgent_requests]), "urgent_requests")
      remove(TalentFolder.where(id: ids[:folders]), "talent_folders")
      remove(BandProject.where(id: ids[:band_projects]), "band_projects")
      remove(CrewPlan.where(id: ids[:crew_plans]), "crew_plans")
    end

    def delete_user_rows(user_ids)
      {
        "job_alerts" => JobAlert.where(user_id: user_ids), "portfolio_items" => PortfolioItem.where(user_id: user_ids),
        "availability_windows" => AvailabilityWindow.where(user_id: user_ids),
        "recent_activities" => RecentActivity.where(user_id: user_ids).or(RecentActivity.where(entity_id: user_ids)),
        "notifications" => Notification.where(user_id: user_ids), "subscriptions" => Subscription.where(user_id: user_ids),
        "email_tokens" => EmailToken.where(user_id: user_ids), "sessions" => Session.where(user_id: user_ids),
        "profiles" => Profile.where(user_id: user_ids)
      }.each { |name, relation| remove(relation, name) }
      remove(User.where(id: user_ids, synthetic_batch: batch), "users")
    end

    def remove(relation, name)
      @counts[name] += relation.delete_all
    end
  end
end
