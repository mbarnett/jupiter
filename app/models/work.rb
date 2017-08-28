class Work < JupiterCore::LockedLdpObject

  ldp_object_includes Hydra::Works::WorkBehavior
  ldp_object_includes AASM

  VISIBILITY_EMBARGO = 'embargo'.freeze

  has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet, :sort]
  has_attribute :subject, ::RDF::Vocab::DC.subject, solrize_for: [:search, :facet]
  has_attribute :creator, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
  has_attribute :dissertant, ::RDF::Vocab::MARCRelators.dis, solrize_for: [:search, :facet]

  has_attribute :contributor, ::RDF::Vocab::DC.contributor, solrize_for: [:search, :facet]
  has_attribute :description, ::RDF::Vocab::DC.description, type: :text, solrize_for: :search
  has_attribute :publisher, ::RDF::Vocab::DC.publisher, solrize_for: [:search, :facet]
  has_attribute :date_created, ::RDF::Vocab::DC.created, solrize_for: [:search, :sort]
  # has_attribute :date_modified, ::RDF::Vocab::DC.modified, type: :date, solrize_for: :sort
  has_attribute :language, ::RDF::Vocab::DC.language, solrize_for: [:search, :facet]
  has_attribute :doi, ::VOCABULARY[:ualib].doi, solrize_for: :exact_match

  has_multival_attribute :member_of_paths, ::VOCABULARY[:ualib].path, solrize_for: :pathing
  has_attribute :embargo_end_date, ::RDF::Vocab::DC.modified, solrize_for: [:search, :sort]

  solr_index :doi_without_label, solrize_for: :exact_match,
                                 as: -> { doi.gsub('doi:', '') if doi.present? }

  attr_accessor :skip_handle_doi_states

  def self.display_attribute_names
    super - [:member_of_paths]
  end

  def self.valid_visibilities
    super + [VISIBILITY_EMBARGO]
  end

  unlocked do
    validates :embargo_end_date, presence: true, if: ->(work) { work.visibility == VISIBILITY_EMBARGO }
    validates :embargo_end_date, absence: true, if: ->(work) { work.visibility != VISIBILITY_EMBARGO }

    after_save :handle_doi_states
    before_destroy :withdraw_doi

    def add_to_path(community_id, collection_id)
      self.member_of_paths += ["#{community_id}/#{collection_id}"]
    end

    aasm do
      state :not_available, initial: true
      state :unminted
      state :excluded
      state :available
      state :awaiting_update

      event :created, after: :queue_create_job do
       transitions from: :not_available, to: :unminted
      end

      event :removed do
       transitions from: :not_available, to: :excluded
      end

      event :unpublish do
       transitions from: [:excluded, :awaiting_update, :unminted], to: :not_available
      end

      event :synced do
       transitions from: [:unminted, :awaiting_update], to: :available
      end

      event :altered, after: :queue_update_job do
       transitions from: [:available, :not_available], to: :awaiting_update
      end
    end

    def doi_permanent_url
     "https://doi.org/#{doi.gsub(/doi:/, '')}" if doi.present?
    end

    def doi_fields_present?
     # TODO: Shouldn't have to do this as these are required fields on the UI.
     # However since no data integrity a GF without these fields is technically valid... have to double check
     title.present? && (creator.present? || dissertant.present?) &&
       resource_type.present? #&& Sufia.config.admin_resource_types[resource_type.first].present?
    end

    private

    def withdraw_doi
     DOIRemovalJob.perform_later(doi) if doi.present?
    end

    def handle_doi_states
     # ActiveFedora doesn't have skip_callbacks built in? So handle this ourselves.
     # Allow this logic to be skipped if skip_handle_doi_states is set.
     # This is mainly used so we can rollback the state when a job fails and
     # we do not wish to rerun all this logic again which would queue up the same job again
     if skip_handle_doi_states.blank?
       return if !doi_fields_present?

       if doi.blank? # Never been minted before
         if !private? && not_available?
           created!(id)
         end
       else
         # If private, we only care if visibility has been made public
         # If public, we care if visibility changed to private or doi fields have been changed
         if (not_available? && transitioned_from_private?) ||
           (available? && (doi_fields_changed? || transitioned_to_private?))
           altered!(id)
         end
       end
     else
       # Return it back to false, so callback can run on the next save
       self.skip_handle_doi_states = false
     end
    end

    def doi_fields_changed?
     [:title, :creator, :year_created, :resource_type].any? do |k|
       if previous_changes.key?(k)
         # check if the changes are actually different
         return true if previous_changes[k][0] != previous_changes[k][1]
       end
     end
     false
    end

    def queue_create_job(work_id)
     DOIServiceJob.perform_later(work_id, 'create')
    end

    def queue_update_job(work_id)
     DOIServiceJob.perform_later(work_id, 'update')
    end
  end
end
