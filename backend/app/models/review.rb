class Review < ApplicationRecord
  belongs_to :author, class_name: "User"
  belongs_to :employer, class_name: "User"
  validates :rating, inclusion: 1..5
  validates :author_id, uniqueness: { scope: :employer_id, message: "has already reviewed this employer" }
  validates :status, inclusion: { in: %w[pending published rejected] }
  validate :author_and_employer_are_different

  private

  def author_and_employer_are_different
    errors.add(:employer, "cannot be the review author") if author_id == employer_id
  end
end
