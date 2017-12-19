class Language < ApplicationRecord

  has_many :draft_items_languages, dependent: :destroy
  has_many :draft_items, through: :draft_items_languages, dependent: :destroy

  def translated_name
    I18n.t(name, scope: [:activerecord, :attributes, :language, :names])
  end

end
