class CreateSiteNotifications < ActiveRecord::Migration[5.1]
  def change
    create_table :site_notifications do |t|
      t.text :message, null: false
      t.belongs_to :user, null: false, foreign_key: true
      t.datetime :removed_at
      t.timestamps
    end
  end
end
