class User < ApplicationRecord

  has_many :identities, dependent: :destroy
  has_many :site_notifications, dependent: :destroy

  # We don't need to validate the format of an email address here,
  # as emails are supplied from SAML (so assuming...hopefully they are valid)
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false }

  validates :display_name, presence: true

end
