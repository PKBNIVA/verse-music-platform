class Message < ApplicationRecord
  # Keeps conversation.updated_at current so inboxes order by latest activity.
  belongs_to :conversation, touch: true
  belongs_to :sender, class_name: "User"
  validates :body, presence: true, length: { maximum: 5_000 }
end
