module Jupiter
  # class for interacting with DOI API using EZID
  class DOIService
    PUBLISHER = 'University of Alberta Libraries'.freeze
    DATACITE_METADATA_SCHEME = {
      'Book' => 'Text/Book',
      'Book Chapter' => 'Text/Chapter',
      'Conference/workshop Poster' => 'Image/Conference Poster',
      'Conference/workshop Presentation' => 'Other/Presentation',
      'Dataset' => 'Dataset',
      'Image' => 'Image',
      'Journal Article (Draft-Submitted)' => 'Text/Submitted Journal Article',
      'Journal Article (Published)' => 'Text/Published Journal Article',
      'Learning Object' => 'Other/Learning Object',
      'Report' => 'Text/Report',
      'Research Material' => 'Other/Research Material',
      'Review' => 'Text/Review',
      'Computing Science Technical Report' => 'Text/Report',
      'Structual Engineering Report' => 'Text/Report',
      'Thesis' => 'Text/Thesis'
    }.freeze

    attr_reader :work

    def initialize(work)
      @work = work
    end

    def create
      @work.unlock_and_fetch_ldp_object do |unlocked_work|
        if unlocked_work.doi_fields_present? && unlocked_work.unminted? && !unlocked_work.private?
          begin
            ezid_identifer = Ezid::Identifier.mint(Ezid::Client.config.default_shoulder, doi_metadata)
            if ezid_identifer.present?
              unlocked_work.doi = ezid_identifer.id
              unlocked_work.synced!
              ezid_identifer
            end
          # EZID API call has probably failed so let's roll back to previous state change
          rescue Exception => e
            # Skip the next handle_doi_states after_save callback and roll back
            # the state to it's previous value. By skipping the callback we can prevent
            # it temporarily from queueing another job. As this could make it end up
            # right back here again resulting in an infinite loop.
            unlocked_work.skip_handle_doi_states = true
            unlocked_work.unpublish!

            raise e
          end
        end
      end
    end

    def update
      @work.unlock_and_fetch_ldp_object do |unlocked_work|
        if unlocked_work.doi_fields_present? && unlocked_work.awaiting_update?
          begin
            ezid_identifer = Ezid::Identifier.modify(unlocked_work.doi, doi_metadata)
            if ezid_identifer.present?
              if unlocked_work.private?
                unlocked_work.unpublish!
              else
                unlocked_work.synced!
              end
              ezid_identifer
            end
          # EZID API call has failed so roll back to previous state change
          rescue Exception => e
            # Skip the next handle_doi_states after_save callback and roll back
            # the state to it's previous value. By skipping the callback we can prevent
            # it temporarily from queueing another job. As this could make it end up
            # right back here again resulting in an infinite loop.
            unlocked_work.skip_handle_doi_states = true
            if unlocked_work.private?
              unlocked_work.synced!
            else
              unlocked_work.unpublish!
            end
            raise e
          end
        end
      end
    end

    def self.remove(doi)
      Ezid::Identifier.modify(doi, status: "#{Ezid::Status::UNAVAILABLE} | withdrawn",
                                   export: 'no')
    end

    private

    # Parse GenericFile and return hash of relevant DOI information
    def doi_metadata
      {
        datacite_creator:  @work.dissertant.present? ? @work.dissertant : @work.creator.join('; '),
        datacite_publisher: PUBLISHER,
        datacite_publicationyear: @work.year_created.present? ? @work.year_created : '(:unav)',
        datacite_resourcetype: DATACITE_METADATA_SCHEME[@work.resource_type.first],
        datacite_title:  @work.title.first,
        target: Rails.application.routes.url_helpers.work_url(id: @work.id),
        # Can only set status if been minted previously, else its public
        status: @work.private? && @work.doi.present? ? "#{Ezid::Status::UNAVAILABLE} | not publicly released" : Ezid::Status::PUBLIC,
        export: @work.private? ? 'no' : 'yes'
      }
    end
  end
end
