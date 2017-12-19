require 'test_helper'

class FileSetTest < ActiveSupport::TestCase

  # TODO: should visibility be a concern here, or does it just inherit from parent item?
  test 'there is no default visibility' do
    file_set = FileSet.new_locked_ldp_object

    assert_nil file_set.visibility
  end

  test 'unknown visibilities are not valid' do
    file_set = FileSet.new_locked_ldp_object

    file_set.unlock_and_fetch_ldp_object do |unlocked_file_set|
      unlocked_file_set.visibility = 'some_fake_visibility'
    end

    assert_not file_set.valid?
    assert file_set.errors[:visibility].present?
    assert_includes file_set.errors[:visibility], 'some_fake_visibility is not a known visibility'
  end

  test 'attaching files' do
    file = ActionDispatch::Http::UploadedFile.new(filename: 'logo_test.png',
                                                  content_type: 'image/png',
                                                  tempfile: File.open(Rails.root + 'app/assets/images/mc_360.png'))

    # It seems unfortunate as a side-effect of improved item validations, we need to create these in tests that
    # don't care about them...
    community = Community.new_locked_ldp_object(title: 'Community', owner: 1).unlock_and_fetch_ldp_object(&:save!)
    collection = Collection.new_locked_ldp_object(title: 'foo', owner: users(:regular_user).id,
                                                  community_id: community.id).unlock_and_fetch_ldp_object(&:save!)

    item = Item.new_locked_ldp_object(title: generate_random_string,
                                      visibility: JupiterCore::VISIBILITY_PUBLIC,
                                      owner: 1,
                                      item_type: CONTROLLED_VOCABULARIES[:item_type].report,
                                      languages: [CONTROLLED_VOCABULARIES[:language].english],
                                      license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)

    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.add_to_path(community.id, collection.id)
      unlocked_item.save!
      unlocked_item.add_files([file])
      unlocked_item.save!
    end

    file_set = item.file_sets.first
    refute file_set.nil?
    assert_equal file_set.contained_filename, 'logo_test.png'
    file_set.unlock_and_fetch_ldp_object do |unlocked_fileset|
      assert unlocked_fileset.original_file.uri =~ /http.*fcrepo\/rest\/.*#{file_set.id}\/files\/.*/
    end
  end

end
