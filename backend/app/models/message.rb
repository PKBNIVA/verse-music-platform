class Message < ApplicationRecord
  # Keeps conversation.updated_at current so inboxes order by latest activity.
  belongs_to :conversation, touch: true
  belongs_to :sender, class_name: "User"
  validates :body, presence: true, length: { maximum: 5_000 }
  # Live delivery to the thread and the recipient's badge (Realtime; polling is the fallback).
  after_create_commit { Realtime.message_created(self) }

  # Messages that matched a scam pattern when sent (see ScamSignals). Matches the partial indexes.
  scope :flagged, -> { where("messages.safety_flags <> '{}'") }

  # Senders who have only sent this many messages so far count as "early" for off-platform pushes.
  EARLY_MESSAGE_COUNT = 3

  def flag_scam_signals
    prior = conversation.messages.where(sender_id:).where.not(id:).count
    self.safety_flags = ScamSignals.detect(body, from_hiring_side: conversation.employer_id == sender_id, early: prior < EARLY_MESSAGE_COUNT)
  end
end
