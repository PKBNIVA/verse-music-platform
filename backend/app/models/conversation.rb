class Conversation < ApplicationRecord
  belongs_to :candidate, class_name: "User"
  belongs_to :employer, class_name: "User"
  belongs_to :job, optional: true
  has_many :messages, dependent: :destroy

  def includes_user?(user) = candidate_id == user.id || employer_id == user.id
end
