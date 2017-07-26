class SiteNotification < ApplicationRecord
  belongs_to :user

  scope :current, -> { where(removed_at: nil) }
  scope :past, -> { where.not(removed_at: nil)}
end
