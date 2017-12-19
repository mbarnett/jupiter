class DraftItem < ApplicationRecord

  enum status: { inactive: 0, active: 1, archived: 2 }

  enum wizard_step: { describe_item: 0, choose_license_and_visibility: 1, upload_files: 2, review_and_deposit_item: 3 }

  enum license: { attribution_noncommercial_4_0_international: 0,
                  attribution_4_0_international: 1,
                  attribution_noncommercial_noderivatives_4_0_international: 2,
                  attribution_noncommercial_sharealike_4_0_international: 3,
                  attribution_noderivatives_4_0_international: 4,
                  attribution_noncommercial_sharealike_4_0_international: 5,
                  cc0_1_0_universal: 6,
                  public_domain_mark_1_0: 7,
                  license_text: 8 }

  # Can't use public as this is a ActiveRecord method
  enum visibility: { open_access: 0,
                     embargo: 1,
                     authenticated: 2 }

  # Can't reuse same keys as visibility, need to differentiate a bit
  enum visibility_after_embargo: { opened: 0,
                                   ccid_protected: 1 }

  has_many_attached :files

  has_many :draft_items_languages, dependent: :destroy

  has_many :languages, through: :draft_items_languages, dependent: :destroy

  # Rails 5 turns presence check on by default for belongs_to relationships
  belongs_to :type, optional: true
  belongs_to :user

  validates :title, :type, :languages,
            :creators, :subjects, :date_created,
            :description, :member_of_paths,
            presence: true, if: :validate_describe_item?

  validates :license, :visibility, presence: true, if: :validate_choose_license_and_visibility?
  validates :license_text_area, presence: true, if: :validate_if_license_is_text?
  validates :embargo_end_date, presence: true, if: :validate_if_visibility_is_embargo?

  validates :files, presence: true, if: :validate_upload_files?

  private

  # TODO: turn on all validations on when reviewing (archived status)
  def validate_describe_item?
    active? && describe_item?
  end

  def validate_choose_license_and_visibility?
    active? && choose_license_and_visibility?
  end

  def validate_upload_files?
    active? && upload_files?
  end

  def validate_if_license_is_text?
    validate_choose_license_and_visibility? && license_text?
  end

  def validate_if_visibility_is_embargo?
    validate_choose_license_and_visibility? && embargo?
  end

end
