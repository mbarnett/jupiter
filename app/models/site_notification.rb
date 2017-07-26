class SiteNotification < ApplicationRecord
  belongs_to :user

  validates :user, presence: true
  validates :message, presence: true

  scope :current, -> { where(removed_at: nil) }
  scope :past, -> { where.not(removed_at: nil)}
end
