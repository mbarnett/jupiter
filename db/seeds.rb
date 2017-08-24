# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

if Rails.env.development?
  require 'active_fedora/cleaner'

  puts 'Starting seeding of dev database...'

  # start fresh
  User.destroy_all
  ActiveFedora::Cleaner.clean!

  # Seed an admin user
  admin = User.create(name: 'Admin', email: 'admin@ualberta.ca', admin: true)
  admin.identities.create(provider: 'developer', uid: 'admin@ualberta.ca')

  # seed work for admin user
  Work.new_cached_remote_object(
    owner: admin.id,
    visibility: JupiterCore::VISIBILITY_PUBLIC,
    title: 'Thesis about cats',
    date_created: Time.zone.now.to_s # will not be required in future, probably will have a created_at field
  ).unlock_cache_and_load_remote_object(&:save!)

  Work.new_cached_remote_object(
    owner: admin.id,
    visibility: JupiterCore::VISIBILITY_PUBLIC,
    title: 'Thesis about dogs',
    date_created: Time.zone.now.to_s
  ).unlock_cache_and_load_remote_object(&:save!)

  Work.new_cached_remote_object(
    owner: admin.id,
    visibility: JupiterCore::VISIBILITY_PUBLIC,
    title: 'Report about stock markets',
    date_created: Time.zone.now.to_s
  ).unlock_cache_and_load_remote_object(&:save!)

  Work.new_cached_remote_object(
    owner: admin.id,
    visibility: JupiterCore::VISIBILITY_PUBLIC,
    title: 'Random images',
    date_created: Time.zone.now.to_s
  ).unlock_cache_and_load_remote_object(&:save!)

  puts 'Database seeded successfully!'
end
