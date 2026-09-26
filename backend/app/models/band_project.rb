class BandProject < ApplicationRecord
  belongs_to :owner, class_name: "User"
  has_many :band_project_roles, dependent: :destroy
  attribute :genres, :json, default: -> { [] }
  validates :name, presence: true, length: { maximum: 120 }
  validate :genres_is_list

  private

  def genres_is_list
    errors.add(:genres, "must be a list") unless genres.is_a?(Array)
  end
end
