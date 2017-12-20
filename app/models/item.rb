
class Item < JupiterCore::LockedLdpObject

  ldp_object_includes Hydra::Works::WorkBehavior

  VISIBILITY_EMBARGO = CONTROLLED_VOCABULARIES[:visibility].embargo.freeze
  VISIBILITIES = (JupiterCore::VISIBILITIES + [VISIBILITY_EMBARGO]).freeze
  VISIBILITIES_AFTER_EMBARGO = [CONTROLLED_VOCABULARIES[:visibility].authenticated,
                                CONTROLLED_VOCABULARIES[:visibility].draft,
                                CONTROLLED_VOCABULARIES[:visibility].public].freeze

  has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :sort]
  has_multival_attribute :creators, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
  has_multival_attribute :contributors, ::RDF::Vocab::DC.contributor, solrize_for: [:search, :facet]
  has_attribute :created, ::RDF::Vocab::DC.created, solrize_for: [:search, :sort]
  has_attribute :sort_year, ::TERMS[:ual].sortyear, solrize_for: [:search, :sort, :facet]
  has_multival_attribute :subject, ::RDF::Vocab::DC.subject, solrize_for: [:search, :facet]
  has_attribute :description, ::RDF::Vocab::DC.description, type: :text, solrize_for: :search
  has_attribute :publisher, ::RDF::Vocab::DC.publisher, solrize_for: [:search, :facet]
  has_multival_attribute :languages, ::RDF::Vocab::DC.language, solrize_for: [:search, :facet]
  has_attribute :embargo_end_date, ::RDF::Vocab::DC.available, type: :date, solrize_for: [:sort]
  has_attribute :license, ::RDF::Vocab::DC.license, solrize_for: [:search]
  has_attribute :rights, ::RDF::Vocab::DC.rights, solrize_for: :exact_match

  # `type` is an ActiveFedora keyword, so we call it `item_type`
  # Note also the `item_type_with_status` below for searching, faceting and forms
  has_attribute :item_type, ::RDF::Vocab::DC.type, solrize_for: :exact_match

  has_attribute :depositor, ::TERMS[:ual].depositor, solrize_for: [:search]
  has_attribute :fedora3_handle, ::TERMS[:ual].fedora3handle, solrize_for: :exact_match
  has_attribute :fedora3_uuid, ::TERMS[:ual].fedora3uuid, solrize_for: :exact_match
  has_attribute :ingest_batch, ::TERMS[:ual].ingestbatch, solrize_for: :exact_match
  has_multival_attribute :member_of_paths, ::TERMS[:ual].path,
                         type: :path,
                         solrize_for: :pathing

  has_attribute :doi, ::TERMS[:prism].doi, solrize_for: :exact_match

  has_attribute :publication_status, ::TERMS[:bibo].status, solrize_for: :exact_match

  has_multival_attribute :embargo_history, ::TERMS[:acl].embargoHistory, solrize_for: :exact_match
  has_attribute :visibility_after_embargo, ::TERMS[:acl].visibilityAfterEmbargo, solrize_for: :exact_match

  additional_search_index :doi_without_label, solrize_for: :exact_match,
                                              as: -> { doi.gsub('doi:', '') if doi.present? }

  # This combines both the controlled vocabulary codes from item_type and published_status above
  # (but only for items that are articles)
  additional_search_index :item_type_with_status,
                          solrize_for: :facet,
                          as: -> { item_type_with_status_code }

  def self.display_attribute_names
    super - [:member_of_paths]
  end

  def self.valid_visibilities
    super + [VISIBILITY_EMBARGO]
  end

  def item_type_with_status_code
    return nil if item_type.blank?
    item_type_code = CONTROLLED_VOCABULARIES[:item_type].from_uri(item_type)
    return item_type_code unless item_type_code == 'article'
    return nil if publication_status.blank?
    publication_status_code = CONTROLLED_VOCABULARIES[:publication_status].from_uri(publication_status)
    "#{item_type_code}_#{publication_status_code}"
  rescue ArgumentError
    return nil
  end

  def file_sets
    FileSet.where(item: id)
  end

  def each_community_collection
    member_of_paths.each do |path|
      community_id, collection_id = path.split('/')
      yield Community.find(community_id), Collection.find(collection_id)
    end
  end

  # TODO: implement me
  def thumbnail
    nil
  end

  def self.from_draft(draft_item)
    attrs = draft_item.attributes.symbolize_keys
    attrs.delete(:id)
    attrs[:visibility] = CONTROLLED_VOCABULARIES[:visibility].public if attrs[:visibility] == 'open_access'
    attrs[:visibility_after_embargo] = nil if attrs[:embargo_end_date].nil?
    attrs[:owner] = attrs[:user_id]

    attrs[:languages] = []
    draft_item.languages.each do |lang|
      attrs[:languages] << ::CONTROLLED_VOCABULARIES[:language].send(lang.name)
    end

    attrs[:item_type] = ::CONTROLLED_VOCABULARIES[:item_type].send(draft_item.type.name)
    attrs[:license] = ::CONTROLLED_VOCABULARIES[:license].send(draft_item.license)

    attrs.keep_if { |k, _| attribute_names.include?(k) }

    new_locked_ldp_object(attrs)
  end

  unlocked do
    validates :embargo_end_date, absence: true, if: ->(item) { item.visibility != VISIBILITY_EMBARGO }
    validates :embargo_end_date, presence: true, if: ->(item) { item.visibility == VISIBILITY_EMBARGO }
    validates :item_type, presence: true, uri: { in_vocabulary: :item_type }
    validates :languages, presence: true, uri: { in_vocabulary: :language }
    validates :license, uri: { in_vocabulary: :license }
    validates :member_of_paths, presence: true
    validates :publication_status, uri: { in_vocabulary: :publication_status }
    validates :title, presence: true
    validates :visibility_after_embargo, absence: true, if: ->(item) { item.visibility != VISIBILITY_EMBARGO }
    validates :visibility_after_embargo, presence: true, if: ->(item) { item.visibility == VISIBILITY_EMBARGO }
    validate :communities_and_collections_must_exist
    validate :license_xor_rights_must_be_present
    validate :publication_status_must_appear_only_for_articles
    validate :visibility_after_embargo_must_be_valid

    before_validation do
      # TODO: for theses, the sort_year attribute should be derived from ual:graduationDate
      begin
        self.sort_year = Date.parse(created).year.to_s if created.present?
      rescue ArgumentError
        # date was unparsable, try to pull out the first 4 digit number as a year
        capture = created.scan(/\d{4}/)
        self.sort_year = capture[0] if capture.present?
      end
    end

    def add_to_path(community_id, collection_id)
      self.member_of_paths += ["#{community_id}/#{collection_id}"]
    end

    def add_communities_and_collections(communities, collections)
      return unless communities.present? && collections.present?
      communities.each_with_index do |community, idx|
        add_to_path(community, collections[idx])
      end
    end

    def add_files(files)
      return if files.blank?
      # Need a item id for file sets to point to
      # TODO should this be a side effect? should we throw an exception if there's no id? Food for thought
      save! if id.nil?

      files.each do |file|
        FileSet.new_locked_ldp_object.unlock_and_fetch_ldp_object do |unlocked_fileset|
          unlocked_fileset.owner = owner
          unlocked_fileset.visibility = visibility
          Hydra::Works::AddFileToFileSet.call(unlocked_fileset, file, :original_file,
                                              update_existing: false, versioning: false)
          unlocked_fileset.member_of_collections += [self]
          # Temporarily cache the file name for storing in Solr
          # if the file was uploaded, it responds to +original_filename+
          # if it's a Ruby File object, it has a +basename+. This distinction seems arbitrary.
          unlocked_fileset.contained_filename = if file.respond_to?(:original_filename)
                                                  file.original_filename
                                                else
                                                  File.basename(file)
                                                end
          unlocked_fileset.save!
          self.members += [unlocked_fileset]
          # pull in hydra derivatives, set temp file base
          # Hydra::Works::CharacterizationService.run(fileset.characterization_proxy, filename)
        end
      end
    end

    def communities_and_collections_must_exist
      return if member_of_paths.blank?
      member_of_paths.each do |path|
        community_id, collection_id = path.split('/')
        community = Community.find_by(community_id)
        errors.add(:member_of_paths, :community_not_found, id: community_id) if community.blank?
        collection = Collection.find_by(collection_id)
        errors.add(:member_of_paths, :collection_not_found, id: collection_id) if collection.blank?
      end
    end

    def license_xor_rights_must_be_present
      # Must have one of license or rights, not both
      if license.blank?
        errors.add(:base, :need_either_license_or_rights) if rights.blank?
      else
        errors.add(:base, :not_both_license_and_rights) if rights.present?
      end
    end

    def visibility_after_embargo_must_be_valid
      return if visibility_after_embargo.nil?
      return if VISIBILITIES_AFTER_EMBARGO.include?(visibility_after_embargo)
      errors.add(:visibility_after_embargo, :not_recognized)
    end

    def publication_status_must_appear_only_for_articles
      if item_type == ::CONTROLLED_VOCABULARIES[:item_type].article && publication_status.blank?
        errors.add(:publication_status, :required_for_article)
      elsif item_type != ::CONTROLLED_VOCABULARIES[:item_type].article && publication_status.present?
        errors.add(:publication_status, :must_be_absent_for_non_articles)
      end
    end
  end

end
