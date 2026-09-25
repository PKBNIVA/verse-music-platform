class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  validates :body, presence: true, length: { maximum: 5_000 }
end
