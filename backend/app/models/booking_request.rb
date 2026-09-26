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
  MAX_BUDGET = 100_000_000

  # Carries a user-facing reason and the HTTP status the API answers with.
  class InvalidTransition < StandardError
    attr_reader :http_status

    def initialize(message = "Invalid booking status change.", http_status: :conflict)
      super(message)
      @http_status = http_status
    end
  end

  belongs_to :act
  belongs_to :requester, class_name: "User"
  has_many :booking_quotes, dependent: :destroy
  has_many :booking_payments, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :event_type, :city, presence: true
  validates :budget_min, :budget_max, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_BUDGET }, allow_nil: true
  validate :budget_range_is_valid

  def latest_quote = booking_quotes.max_by(&:created_at)

  def transition_to!(new_status, actor:)
    new_status = new_status.to_s
    raise InvalidTransition.new("Unknown booking status.", http_status: :bad_request) unless STATUSES.include?(new_status)

    with_lock do
      owner = act.owner_id == actor.id
      raise InvalidTransition.new("Booking not found", http_status: :not_found) unless owner || requester_id == actor.id

      transitions = owner ? OWNER_TRANSITIONS : REQUESTER_TRANSITIONS
      unless transitions.fetch(status, []).include?(new_status)
        other = owner ? REQUESTER_TRANSITIONS : OWNER_TRANSITIONS
        if other.fetch(status, []).include?(new_status)
          party = owner ? "person who sent the enquiry" : "act owner"
          raise InvalidTransition.new("Only the #{party} can mark this booking #{new_status}.", http_status: :forbidden)
        end
        raise InvalidTransition.new("This booking is #{status} and cannot be marked #{new_status}.")
      end
      if new_status == "accepted"
        # Accepting without a live quote leaves the buyer with nothing to pay a deposit against.
        quote = booking_quotes.order(created_at: :desc).first
        raise InvalidTransition.new("There is no quote to accept yet. Ask the act for a quote first.") unless quote
        raise InvalidTransition.new("This quote has expired. Ask the act for a new quote.") if quote.valid_until.present? && quote.valid_until <= Time.current
        quote.update!(status: "accepted")
      end

      update!(status: new_status)
    end
  end

  private

  def budget_range_is_valid
    errors.add(:budget_max, "must be at least the minimum budget") if budget_min && budget_max && budget_max < budget_min
  end
end
