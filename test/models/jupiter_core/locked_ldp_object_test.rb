require 'test_helper'

class LockedLdpObjectTest < ActiveSupport::TestCase

  @@klass = Class.new(JupiterCore::LockedLdpObject) do
    ldp_object_includes Hydra::Works::WorkBehavior
    has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    has_attribute :creator, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
    has_multival_attribute :member_of_paths, ::VOCABULARY[:ualib].path, solrize_for: :pathing

    solr_calculated_attribute :my_solr_doc_attr, solrize_for: :search do
      'a_test_value'
    end

    def locked_method_shouldnt_mutate(attempted_title)
      self.title = attempted_title
    end

    def safe_locked_method
      "Title is: #{title}"
    end

    unlocked do
      def unlocked_method_can_mutate(attempted_title)
        self.title = attempted_title
      end

      def unlocked_method_dont_let_locked_methods_mutate(attempted_title)
        locked_method_shouldnt_mutate(attempted_title)
      end
    end
  end

  # this fails if the call to super doesn't happen in JupiterCore::LockedLdpObject.inherited
  test 'inheritance is being tracked properly' do
    assert_includes JupiterCore::LockedLdpObject.descendants, @@klass
  end

  test 'the list of safe attributes never includes the id' do
    JupiterCore::LockedLdpObject.descendants.each do |klass|
      assert_not_includes klass.safe_attributes, :id
    end
  end

  test 'the shared indexer is being used' do
    assert_equal @@klass.send(:derived_af_class).indexer, JupiterCore::Indexer
  end

  test 'derived AF objects are including the proper modules' do
    assert @@klass.send(:derived_af_class).include? Hydra::Works::WorkBehavior
  end

  test 'attribute definitions are working' do
    assert_equal [:creator, :id, :member_of_paths, :owner, :title, :visibility], @@klass.attribute_names.sort
  end

  test 'attribute metadata is being tracked properly' do
    title_metadata = @@klass.attribute_metadata(:title)

    assert_instance_of Hash, title_metadata
    assert_equal ::RDF::Vocab::DC.title, title_metadata[:predicate]
    assert_equal :string, title_metadata[:type]
    assert_not title_metadata[:multiple]
    assert_equal [:search, :facet], title_metadata[:solrize_for]
    assert_equal ['title_tesim', 'title_sim'], title_metadata[:solr_names]

    assert @@klass.attribute_metadata(:member_of_paths)[:multiple]
  end

  test 'solr calculated attributes are working properly' do
    obj = @@klass.new_locked_ldp_object(title: generate_random_string)

    obj.unlock_and_fetch_ldp_object do |uo|
      solr_doc = uo.to_solr
      assert solr_doc.key? 'my_solr_doc_attr_tesim'
      assert_includes solr_doc['my_solr_doc_attr_tesim'], 'a_test_value'
    end
  end

  test 'reverse solr name lookup is working properly' do
    assert_equal :title, @@klass.solr_name_to_attribute_name('title_tesim')
    assert_equal :member_of_paths, @@klass.solr_name_to_attribute_name('member_of_paths_dpsim')
  end

  test 'the default constructor is private' do
    assert_raises ::NoMethodError do
      @@klass.new
    end
  end

  test 'locked objects are not mutatable' do
    original_title = generate_random_string
    obj = @@klass.new_locked_ldp_object(title: original_title)

    assert_equal original_title, obj.title

    assert_raises JupiterCore::LockedInstanceError do
      obj.title = generate_random_string
    end

    assert_raises JupiterCore::LockedInstanceError do
      obj.locked_method_shouldnt_mutate(generate_random_string)
    end

    assert_raises JupiterCore::LockedInstanceError do
      obj.unlocked_method_can_mutate(generate_random_string)
    end

    assert_raises JupiterCore::LockedInstanceError do
      obj.unlock_and_fetch_ldp_object { |uo| uo.unlocked_method_dont_let_locked_methods_mutate(generate_random_string) }
    end

    assert_equal original_title, obj.title
  end

  test 'unlocked methods can call locked objects' do
    title = generate_random_string
    obj = @@klass.new_locked_ldp_object(title: title)

    obj.unlock_and_fetch_ldp_object do |uo|
      assert_equal "Title is: #{title}", uo.safe_locked_method
    end
  end

  test 'unlocked methods can perform mutation' do
    orig_title = generate_random_string
    obj = @@klass.new_locked_ldp_object(title: orig_title)

    new_title = generate_random_string

    obj.unlock_and_fetch_ldp_object do |unlocked_object|
      assert_equal orig_title, unlocked_object.title
      unlocked_object.title = new_title
    end

    assert_equal new_title, obj.title

    another_new_title = generate_random_string

    obj.unlock_and_fetch_ldp_object do |unlocked_object|
      unlocked_object.unlocked_method_can_mutate(another_new_title)
    end

    assert_equal another_new_title, obj.title
  end

  test '#inspect works as expected' do
    title = generate_random_string
    obj = @@klass.new_locked_ldp_object(title: title)
    assert_equal "#<AnonymousClass id: nil, visibility: nil, owner: nil, title: \"#{title}\", creator: nil,"\
                 ' member_of_paths: []>', obj.inspect
  end

  test 'attribute inheritance is working' do
    subclass = Class.new(@@klass) do
      has_attribute :subject, ::RDF::Vocab::DC.subject, solrize_for: :search
    end

    assert_equal [:creator, :id, :member_of_paths, :owner, :subject, :title, :visibility], subclass.attribute_names.sort
    # ensure mutating subclass attribute lists isn't trickling back to the superclass
    assert_equal [:creator, :id, :member_of_paths, :owner, :title, :visibility], @@klass.attribute_names.sort
  end

  test 'attributes are declaring properly' do
    title = generate_random_string
    obj = @@klass.new_locked_ldp_object(title: title)
    assert obj.attributes.key? 'title'
    assert_equal title, obj.attributes['title']
    assert obj.attributes.key? 'id'

    assert obj.display_attributes.key? 'title'
    assert_not obj.display_attributes.key? 'id'
    assert_equal title, obj.display_attributes['title']
  end

  test 'active model integration is working' do
    obj = @@klass.new_locked_ldp_object

    assert_instance_of ActiveModel::Errors, obj.errors
    assert_not_predicate obj.errors, :any?
    assert_not_predicate obj, :persisted?
    assert_not_predicate obj, :changed?
    assert_not_predicate obj, :valid?

    obj.unlock_and_fetch_ldp_object do |uo|
      uo.title = 'Title'
      uo.visibility = :public
    end

    assert_predicate obj, :changed?
    assert_predicate obj, :valid?
  end

  test 'solr integration is working' do
    assert @@klass.all.count == 0

    creator = generate_random_string
    first_title = generate_random_string

    obj = @@klass.new_locked_ldp_object(title: first_title, creator: creator, visibility: :public)
    obj.unlock_and_fetch_ldp_object(&:save!)

    assert obj.id.present?

    assert @@klass.all.count == 1

    assert_equal first_title, @@klass.all.first.title

    second_title = generate_random_string

    another_obj = @@klass.new_locked_ldp_object(title: second_title, creator: creator, visibility: :public)
    another_obj.unlock_and_fetch_ldp_object(&:save!)

    assert @@klass.all.count == 2

    assert @@klass.where(title: second_title).present?
    assert @@klass.where(title: second_title).first.id == another_obj.id

    assert_raises JupiterCore::ObjectNotFound do
      @@klass.find(generate_random_string)
    end

    assert @@klass.find(obj.id).present?

    search_results = @@klass.search(q: '')

    assert search_results.count == 2

    search_results.results.each do |res|
      assert_includes [obj, another_obj].map(&:id), res.id
    end

    search_results.each_facet_with_results do |facet|
      assert_includes ['Title', 'Creator', 'Visibility'], facet.name
      if facet.name == 'Title'
        assert facet.values.keys.count == 2
        assert facet.values.key?(first_title)
        assert facet.values.key?(second_title)
        [first_title, second_title].each do |title|
          assert facet.values[title] == 1
        end
      elsif facet.name == 'Creator'
        assert facet.values.keys.count == 1
        assert facet.values.key?(creator)
        assert facet.values[creator] == 2
      elsif facet.name == 'Visibility'
        assert facet.values.keys.count == 1
        assert facet.values.key?('public')
        assert facet.values['public'] == 2
      end
    end
  end

end
