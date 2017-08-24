class SearchTest < ActiveSupport::TestCase

  @@klass = Class.new(JupiterCore::CachedRemoteObject) do
    remote_object_includes Hydra::Works::WorkBehavior
    has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    has_attribute :creator, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
    has_multival_attribute :member_of_paths, ::VOCABULARY[:ualib].path, solrize_for: :pathing

    solr_index :my_solr_doc_attr, solrize_for: :search, as: -> { 'a_test_value' }

    def locked_method_shouldnt_mutate(attempted_title)
      self.title = attempted_title
    end

    def safe_locked_method
      "Title is: #{title}"
    end

    when_mutating_remote_object do
      def unlocked_method_can_mutate(attempted_title)
        self.title = attempted_title
      end

      def unlocked_method_dont_let_locked_methods_mutate(attempted_title)
        locked_method_shouldnt_mutate(attempted_title)
      end
    end
  end

  test 'basic search functionality' do
    first_title = generate_random_string
    second_title = generate_random_string
    creator = generate_random_string

    obj = @@klass.new_cached_remote_object(title: first_title, creator: creator, visibility: 'public',
                                           owner: users(:regular_user).id)
    another_obj = @@klass.new_cached_remote_object(title: second_title, creator: creator, visibility: 'public',
                                                   owner: users(:regular_user).id)
    a_private_object = @@klass.new_cached_remote_object(title: generate_random_string, creator: generate_random_string,
                                                        visibility: 'private', owner: users(:regular_user).id)

    obj.flush_cache_and_mutate_remote(&:save!)
    another_obj.flush_cache_and_mutate_remote(&:save!)
    a_private_object.flush_cache_and_mutate_remote(&:save!)

    search_results = JupiterCore::Search.search(models: @@klass, q: '')

    assert search_results.count == 2

    search_results.results.each do |res|
      assert_includes [obj, another_obj].map(&:id), res.id
      assert_not res.id == a_private_object.id
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
