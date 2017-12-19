class CreateDraftItemTables < ActiveRecord::Migration[5.1]

  def change
    create_table :types do |t|
      t.string :name, null: false

      t.timestamps
    end

    create_table :draft_items do |t|
      t.string :uuid

      t.integer :status, default: 0, null: false
      t.integer :wizard_step, default: 0, null: false

      t.integer :thumbnail_id
      t.string :title
      t.string :alternate_title
      t.date :date_created
      t.text :description
      t.string :source
      t.string :related_item

      t.integer :license, default: 0, null: false
      t.text :license_text_area

      t.integer :visibility, default: 0, null: false
      t.datetime :embargo_end_date
      t.integer :visibility_after_embargo, default: 0, null: false

      t.references :type, index: true
      t.references :user, null: false, index: true, foreign_key: true

      t.json :creators, array: true
      t.json :subjects, array: true
      t.json :member_of_paths, array: true
      t.json :contributors, array: true
      t.json :places, array: true
      t.json :time_periods, array: true
      t.json :citations, array: true

      t.timestamps
    end

    create_table :languages do |t|
      t.string :name, null: false

      t.timestamps
    end

    create_table :draft_items_languages, id: false do |t|
      t.references :draft_item, index: true
      t.references :language, index: true

      t.timestamps
    end
  end

end
