class BookingRequest < ApplicationRecord
  STATUSES = %w[requested viewed negotiating quoted accepted completed disputed declined cancelled].freeze
  OWNER_TRANSITIONS = {
    "requested" => %w[viewed negotiating declined], "viewed" => %w[negotiating declined],
    "quoted" => %w[negotiating declined], "negotiating" => %w[declined],
    "accepted" => %w[completed disputed]
  }.freeze
  REQUESTER_TRANSITIONS = {
    "requested" => %w[negotiating cancelled], "viewed" => %w[negotiating cancelled],
    "quoted" => %w[accepted negotiating cancelled], "negotiating" => %w[accepted cancelled],
    "accepted" => %w[cancelled disputed]
  }.freeze

  class InvalidTransition < StandardError; end

  belongs_to :act
  belongs_to :requester, class_name: "User"
  has_many :booking_quotes, dependent: :destroy
  has_many :booking_payments, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  def transition_to!(new_status, actor:)
    with_lock do
      transitions = if act.owner_id == actor.id
        OWNER_TRANSITIONS
      elsif requester_id == actor.id
        REQUESTER_TRANSITIONS
      else
        {}
      end
      raise InvalidTransition unless transitions.fetch(status, []).include?(new_status)

      update!(status: new_status)
    end
  end
end
