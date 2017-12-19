require 'test_helper'

class ItemTest < ActiveSupport::TestCase

  test 'a valid item can be constructed' do
    community = Community.new_locked_ldp_object(title: 'Community', owner: 1,
                                                visibility: JupiterCore::VISIBILITY_PUBLIC)
    community.unlock_and_fetch_ldp_object(&:save!)
    collection = Collection.new_locked_ldp_object(title: 'Collection', owner: 1,
                                                  visibility: JupiterCore::VISIBILITY_PUBLIC,
                                                  community_id: community.id)
    collection.unlock_and_fetch_ldp_object(&:save!)
    item = Item.new_locked_ldp_object(title: 'Item', owner: 1, visibility: JupiterCore::VISIBILITY_PUBLIC,
                                      languages: [CONTROLLED_VOCABULARIES[:language].english],
                                      license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international,
                                      item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                      publication_status: CONTROLLED_VOCABULARIES[:publication_status].draft)
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.add_to_path(community.id, collection.id)
      unlocked_item.save!
    end
    assert item.valid?
  end

  test 'there is no default visibility' do
    item = Item.new_locked_ldp_object

    assert_nil item.visibility
  end

  test 'unknown visibilities are not valid' do
    item = Item.new_locked_ldp_object

    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = 'some_fake_visibility'
    end

    assert_not item.valid?
    assert item.errors[:visibility].present?
    assert_includes item.errors[:visibility], 'some_fake_visibility is not a known visibility'
  end

  test 'embargo is a valid visibility for items' do
    assert_includes Item.valid_visibilities, Item::VISIBILITY_EMBARGO
  end

  test 'created allows fuzzy dates' do
    item = Item.new_locked_ldp_object
    assert_nothing_raised do
      item.unlock_and_fetch_ldp_object do |unlocked_item|
        unlocked_item.created = 'before 1997 or after 2084'
      end
    end
    assert_not item.valid?
    assert_equal '1997', item.sort_year
  end

  test 'embargo_end_date must be present if visibility is embargo' do
    item = Item.new_locked_ldp_object
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = Item::VISIBILITY_EMBARGO
    end

    assert_not item.valid?
    assert item.errors[:embargo_end_date].present?
    assert_includes item.errors[:embargo_end_date], "can't be blank"
  end

  test 'embargo_end_date must be blank for non-embargo visibilities' do
    item = Item.new_locked_ldp_object
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = JupiterCore::VISIBILITY_PUBLIC
      unlocked_item.embargo_end_date = '1992-02-01'
    end

    assert_not item.valid?
    assert item.errors[:embargo_end_date].present?
    assert_includes item.errors[:embargo_end_date], 'must be blank'

    refute item.errors[:visibility].present?
  end

  test 'visibility_after_embargo must be present if visibility is embargo' do
    item = Item.new_locked_ldp_object
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = Item::VISIBILITY_EMBARGO
    end

    assert_not item.valid?
    assert item.errors[:visibility_after_embargo].present?
    assert_includes item.errors[:visibility_after_embargo], "can't be blank"
  end

  test 'visibility_after_embargo must be blank for non-embargo visibilities' do
    item = Item.new_locked_ldp_object
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = JupiterCore::VISIBILITY_PUBLIC
      unlocked_item.visibility_after_embargo = CONTROLLED_VOCABULARIES[:visibility].draft
    end

    assert_not item.valid?
    assert item.errors[:visibility_after_embargo].present?
    assert_includes item.errors[:visibility_after_embargo], 'must be blank'
    # Make sure no controlled vocabulary error
    refute_includes item.errors[:visibility_after_embargo], 'is not recognized'

    refute item.errors[:visibility].present?
  end

  test 'visibility_after_embargo must be from the controlled vocabulary' do
    item = Item.new_locked_ldp_object
    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.visibility = Item::VISIBILITY_EMBARGO
      unlocked_item.visibility_after_embargo = 'whatever'
    end

    assert_not item.valid?
    assert item.errors[:visibility_after_embargo].present?
    assert_includes item.errors[:visibility_after_embargo], 'is not recognized'
    refute item.errors[:visibility].present?
  end

  test '#add_to_path assigns paths properly' do
    item = Item.new_locked_ldp_object
    community_id = generate_random_string
    collection_id = generate_random_string

    item.unlock_and_fetch_ldp_object do |unlocked_item|
      unlocked_item.add_to_path(community_id, collection_id)
    end

    assert_includes item.member_of_paths, "#{community_id}/#{collection_id}"
  end

  test 'member_of_paths is not a display attribute' do
    assert_not_includes Item.display_attribute_names, :member_of_paths
  end

  test 'a community/collection path must be present' do
    item = Item.new_locked_ldp_object

    assert_not item.valid?
    assert_includes item.errors[:member_of_paths], "can't be blank"
  end

  test 'community/collection must exist' do
    item = Item.new_locked_ldp_object
    community_id = generate_random_string
    collection_id = generate_random_string
    item.unlock_and_fetch_ldp_object do |unlocked|
      unlocked.add_to_path(community_id, collection_id)
    end

    assert_not item.valid?
    assert_includes item.errors[:member_of_paths],
                    I18n.t('activemodel.errors.models.ir_item.attributes.member_of_paths.community_not_found',
                           id: community_id)
    assert_includes item.errors[:member_of_paths],
                    I18n.t('activemodel.errors.models.ir_item.attributes.member_of_paths.collection_not_found',
                           id: collection_id)
  end

  test 'a language must be present' do
    item = Item.new_locked_ldp_object

    assert_not item.valid?
    assert_includes item.errors[:languages], "can't be blank"
  end

  test 'a language must be from the controlled vocabulary' do
    item = Item.new_locked_ldp_object(languages: ['whatever'])
    assert_not item.valid?
    assert_includes item.errors[:languages], 'is not recognized'

    item = Item.new_locked_ldp_object(languages: [CONTROLLED_VOCABULARIES[:language].english])
    assert_not item.valid?
    refute_includes item.errors.keys, :languages
  end

  test 'a license or rights statement must be present' do
    item = Item.new_locked_ldp_object

    assert_not item.valid?
    assert_includes item.errors[:base], 'must have either a license or a rights statement'
  end

  test 'a rights statement must not be present if a license is present' do
    item = Item.new_locked_ldp_object(rights: 'Share my work with everybody',
                                      license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)

    assert_not item.valid?
    assert_includes item.errors[:base], 'should not have both a license and a rights statement'
  end

  test 'a license must be from the controlled vocabulary' do
    item = Item.new_locked_ldp_object(license: 'whatever')
    assert_not item.valid?
    assert_includes item.errors[:license], 'is not recognized'

    item = Item.new_locked_ldp_object(license: CONTROLLED_VOCABULARIES[:license].attribution_4_0_international)
    assert_not item.valid?
    refute_includes item.errors.keys, :license
  end

  test 'an item type is required' do
    item = Item.new_locked_ldp_object
    assert_not item.valid?
    assert_includes item.errors[:item_type], "can't be blank"
  end

  test 'an item type must come from the controlled vocabulary' do
    item = Item.new_locked_ldp_object(item_type: 'whatever')
    assert_not item.valid?
    assert_includes item.errors[:item_type], 'is not recognized'
  end

  test 'publication status is needed for articles' do
    item = Item.new_locked_ldp_object(item_type: CONTROLLED_VOCABULARIES[:item_type].article)
    assert_not item.valid?
    assert_includes item.errors[:publication_status], 'is required for articles'
  end

  test 'publication status must come from controlled vocabulary' do
    item = Item.new_locked_ldp_object(item_type: CONTROLLED_VOCABULARIES[:item_type].article,
                                      publication_status: 'whatever')
    assert_not item.valid?
    assert_includes item.errors[:publication_status], 'is not recognized'
  end

  test 'publication status must be absent for non-articles' do
    item = Item.new_locked_ldp_object(item_type: CONTROLLED_VOCABULARIES[:item_type].book,
                                      publication_status: CONTROLLED_VOCABULARIES[:publication_status].published)
    assert_not item.valid?
    assert_includes item.errors[:publication_status], 'must be absent for non-articles'
  end

end
