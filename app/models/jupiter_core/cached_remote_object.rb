# JupiterCore::CachedRemoteObject classes are lightweight, read-only objects
# TODO: this file could benefit from some reorganization, possibly into several
# files
module JupiterCore
  class ObjectNotFound < StandardError; end
  class PropertyInvalidError < StandardError; end
  class MultipleIdViolationError < StandardError; end
  class AlreadyDefinedError < StandardError; end
  class LockedInstanceError < StandardError; end

  VISIBILITY_PUBLIC = 'public'.freeze
  VISIBILITY_PRIVATE = 'private'.freeze
  VISIBILITY_AUTHENTICATED = 'authenticated'.freeze

  class CachedRemoteObject

    include ActiveModel::Model
    include ActiveModel::Serializers::JSON

    include Kaminari::ConfigurationMethods

    # Prefix added to subclass names to derive the name of their corresponding +ActiveFedora+ LDP object
    AF_CLASS_PREFIX = 'IR'.freeze

    # Maps semantically meaningful, easily understandable names for solr index behaviours
    # into the sometimes inscrutable and opaque descriptors used by Solrizer. See:
    # https://github.com/mbarnett/solrizer/blob/e5dd2bd571b9ebdb8a8ab214574075c28951e53e/lib/solrizer/default_descriptors.rb
    SOLR_DESCRIPTOR_MAP = {
      search: :stored_searchable,
      sort: :stored_sortable,
      facet: :facetable,
      exact_match: :symbol,
      pathing: :descendent_path
    }.freeze

    # we reserve .new for internal use in constructing CachedRemoteObjects. Use the public interface
    # +new_cached_remote_object+ for constructing new objects externally.
    private_class_method :new

    # inheritable class attributes (not all class-level attributes in this class should be inherited,
    # these are the inheritance-safe attributes)
    class_attribute :af_parent_class, :attribute_cache, :attribute_names, :facets,
                    :reverse_solr_name_cache, :solr_calc_attributes

    # Returns the id of the object in LDP as a String
    def id
      return remote_object.send(:id) if remote_object.present?
      solr_representation['id'] if solr_representation
    end

    # Provides structured, mediated interaction for mutating the underlying LDP object
    #
    # yields the underlying mutable +ActiveFedora+ object to the block and returns self for chaining
    #
    #  locked_obj.flush_cache_and_perform_remote_write do |object|
    #    object.title = 'asdf'
    #    object.save
    #  end
    def flush_cache_and_perform_remote_write
      self.remote_object = self.class.send(:derived_af_class).find(id) unless @remote_object.present?
      yield @remote_object
      self
    end

    # Returns name-value pairs for all of the LDP Object's attributes as a Hash
    def attributes
      self.class.attribute_names.map do |name|
        [name.to_s, send(name)]
      end.to_h
    end

    # Returns name-value pairs for the LDP Object's attributes named by +display_attribute_names+ as a Hash
    def display_attributes
      self.class.display_attribute_names.map do |name|
        [name.to_s, send(name)]
      end.to_h
    end

    # A better debug representation for LDP Objects
    def inspect
      "#<#{self.class.name || 'AnonymousClass'} " + self.class.attribute_names.map do |name|
        val = send(name)
        val_display = if val.is_a?(String)
                        %Q("#{val}")
                      elsif val.nil?
                        'nil'
                      elsif val.is_a?(DateTime)
                        val.utc.iso8601(3)
                      elsif val.is_a?(Enumerable) && val.empty?
                        '[]'
                      else
                        val.to_s
                      end
        "#{name}: #{val_display}"
      end.join(', ') + '>'
    end

    # Has this object been persisted? (Defined for ActiveModel compatibility)
    def persisted?
      # if we haven't had to load the internal remote_object, by definition we must by synced to disk
      return true unless remote_object.present?
      remote_object.persisted?
    end

    # Has this object been changed since being loaded? (Defined for ActiveModel compatibility)
    def changed?
      return false unless remote_object.present?
      remote_object.changed?
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def valid?(*args)
      return super(*args) unless remote_object.present?
      remote_object.valid?(*args)
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def errors
      return super unless remote_object.present?
      remote_object.errors
    end

    # Use this to create a new +CachedRemoteObjects+ and its underlying LDP instance. attrs populate the new object's
    # attributes
    def self.new_cached_remote_object(*attrs)
      new(ldp_obj: derived_af_class.new(*attrs))
    end

    # Override this in your subclasses to control what attributes are automatically listed in the attributes list
    def self.display_attribute_names
      attribute_names - [:id]
    end

    # An array of attribute names that are safe to be used for safe_params calls in controllers. ID is _never_ a safe
    # attribute for forms to modify. Subclasses should override this and remove any other sensitive attributes from
    # this array
    #
    # a Work +CachedRemoteObject+ might choose to protect its +owner+ attribute by overriding this method:
    #
    #  def self.safe_attributes
    #    super - [:owner]
    #  end
    #
    # and then enforce that in a controller like works_controller.rb:
    #    def work_params
    #      params[:work].permit(Work.safe_attributes)
    #    end
    def self.safe_attributes
      attribute_names - [:id]
    end

    # Accepts a symbol representing the attribute name, and returns a Hash containing
    # metadata about an object's attributes.
    #
    # Given a subclass +Work+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then the Hash returned by <tt>Work.attribute_metadata(:title)</tt> would be:
    #   {
    #      :predicate => #<RDF::Vocabulary::Term:0x3fe32a1d1a30 URI:http://purl.org/dc/terms/title>,
    #      :multiple => false,
    #      :solrize_for => [:search, :facet],
    #      :type => :string,
    #      :solr_names => ["title_tesim", "title_sim"]
    #   }
    def self.attribute_metadata(attribute_name)
      attribute_cache[attribute_name]
    end

    # Accepts a String name of a name-mangled solr field, and returns the symbol of the attribute that corresponds to it
    #
    # Given a subclass +Work+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then:
    #   Work.solr_name_to_attribute_name('title_tesim')
    #   => :title
    def self.solr_name_to_attribute_name(solr_name)
      reverse_solr_name_cache[solr_name]
    end

    # Accepts a string id of an object in the LDP, and returns a +CachedRemoteObjects+ representation of that object
    # or raises <tt>JupiterCore::ObjectNotFound</tt> if there is no object corresponding to that id
    def self.find(id)
      results_count, results, _ = JupiterCore::Search.perform_solr_query(q: %Q(_query_:"{!raw f=id}#{id}"),
                                                                         restrict_to_model: derived_af_class)

      raise ObjectNotFound, "Couldn't find #{self} with id='#{id}'" if results_count == 0
      raise MultipleIdViolationError if results_count > 1

      new(solr_doc: results.first)
    end

    # Returns an array of all +CachedRemoteObject+ in the LDP
    # def self.all(limit:, offset: )
    def self.all
      JupiterCore::DeferredSolrQuery.new(self)
    end

    # Integer, the number of records in Solr/Fedora
    def self.count
      all.count
    end

    # Accepts a hash of name-value pairs to query for, and returns an Array of matching +CachedRemoteObject+
    #
    # For example:
    #   Work.where(title: 'Test upload')
    #    => [#<Work id: "e5f4a074-5bcb-48a4-99ee-12bc83cef291", title: "Test upload", subject: "", creator: "", contributor: "", description: "", publisher: "", date_created: "", language: "", doi: "", member_of_paths: ["98124366-c8b2-487a-95f0-a1c18c805ddd/799e2eee-5435-4f08-bf3d-fc256fee9447"]>
    def self.where(attributes)
      all.where(attributes)
    end

    # num, an Integer limiting the number of results returned
    def self.limit(num)
      all.limit(num)
    end

    # num, an Integer indicating the offset the results returned begin at
    def self.offset(num)
      all.offset(num)
    end

    # attr, a string attribute name and sort order
    def self.sort(attr, order = :asc)
      all.sort(attr, order)
    end

    # the least recently created record in Solr, as determined by the record_created_at timestamp
    def self.first
      all.limit(1).sort(:record_created_at, :asc).first
    end

    # the most recently created record in Solr, as determined by the record_created_at timestamp
    def self.last
      all.limit(1).sort(:record_created_at, :desc).first
    end

    def self.valid_visibilities
      [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE, VISIBILITY_AUTHENTICATED]
    end

    def public?
      visibility == VISIBILITY_PUBLIC
    end

    def private?
      visibility == VISIBILITY_PRIVATE
    end

    def authenticated?
      visibility == VISIBILITY_AUTHENTICATED
    end

    # Used to dynamically turn an arbitrary Solr document into an instance of its originating class
    #
    # eg)
    #    2.4.0 :003 > solr_doc
    #    => {"system_create_dtsi"=>"2017-08-01T17:07:08Z", "system_modified_dtsi"=>"2017-08-01T17:07:08Z", "has_model_ssim"=>["IRWork"], "id"=>"88489b6e-12dd-4eea-b833-af08782c419e", "visibility_ssim"=>["public"], "owner_ssim"=>[""], "title_tesim"=>["Test"], "subject_tesim"=>[""], "creator_tesim"=>[""], "contributor_tesim"=>[""], "description_tesim"=>[""], "publisher_tesim"=>[""], "date_created_tesim"=>[""], "date_created_ssi"=>"", "language_tesim"=>[""], "doi_ssim"=>[""], "member_of_paths_dpsim"=>["6d0a8efa-ec6e-4fb9-bd67-e7877376c5ca/7e5d0653-fcb0-45a1-bb9c-ec3b896afcba"], "embargo_end_date_tesim"=>[""], "embargo_end_date_ssi"=>"", "_version_"=>1574549301238956032, "timestamp"=>"2017-08-01T17:07:08.507Z", "score"=>2.5686157}
    #    2.4.0 :004 > JupiterCore::CachedRemoteObject.reify_solr_doc(solr_doc)
    #    => #<Work id: "88489b6e-12dd-4eea-b833-af08782c419e", visibility: "public", owner: "", title: "Test", subject: "", creator: "", contributor: "", description: "", publisher: "", date_created: "", language: "", doi: "", member_of_paths: ["6d0a8efa-ec6e-4fb9-bd67-e7877376c5ca/7e5d0653-fcb0-45a1-bb9c-ec3b896afcba"], embargo_end_date: "">
    #
    def self.reify_solr_doc(solr_doc)
      raise ArgumentError, 'Not a valid CachedRemoteObject representation' unless solr_doc['has_model_ssim'].present?
      solr_doc['has_model_ssim'].first.constantize.owning_class.send(:new, solr_doc: solr_doc)
    end

    private

    attr_reader :remote_object
    attr_accessor :solr_representation

    def initialize(solr_doc: nil, ldp_obj: nil)
      raise ArgumentError if solr_doc.present? && ldp_obj.present?
      self.solr_representation = solr_doc if solr_doc.present?
      self.remote_object = ldp_obj if ldp_obj.present?
    end

    def method_missing(name, *args, &block)
      return super unless self.class.send(:derived_af_class).instance_methods.include?(name)
      raise LockedInstanceError, 'This is a locked cache instance and does not respond to the method you attempted '\
                                 "to call (##{name}). However, the locked instance DOES respond to ##{name}. Use "\
                                 'flush_cache_and_perform_remote_write to load a writable copy (SLOW).'
    end

    # Looks pointless, but keeps rubocop happy because of the error-message refining +method_missing+ above
    def respond_to_missing?(*_args); super; end

    def remote_object=(obj)
      @remote_object = obj
      @remote_object.owning_object = self

      # NOTE: it's important to establish the owning object PRIOR to calling to_solr, as solr_calc_properties
      # could need to call methods that get forwarded to the owning object
      @solr_representation = @remote_object.to_solr
      @remote_object
    end

    # private class methods
    class << self

      # Kaminari integration
      define_method Kaminari.config.page_method_name, (proc { |num|
        limit(default_per_page).offset(default_per_page * ([num.to_i, 1].max - 1))
      })

      private

      # Clones inherited arrays/maps so that local mutation doesn't propogate to the parent
      # also sets up basic attributes that every child class has: +id+, +owner+, and +visibility+
      def inherited(child)
        super
        child.attribute_names = attribute_names ? attribute_names.dup : [:id]
        child.reverse_solr_name_cache = reverse_solr_name_cache ? reverse_solr_name_cache.dup : {}
        child.attribute_cache = attribute_cache ? attribute_cache.dup : {}
        child.facets = facets ? facets.dup : []
        child.solr_calc_attributes = solr_calc_attributes.present? ? solr_calc_attributes.dup : {}
        # child.derived_af_class

        # If there's no class between +CachedRemoteObject+ and this child that's
        # already had +visibility+ and +owner+ defined, define them.
        child.class_eval do
          unless attribute_names.include?(:visibility)
            has_attribute :visibility, ::VOCABULARY[:jupiter_core].visibility, solrize_for: [:exact_match, :facet]
          end
          unless attribute_names.include?(:owner)
            has_attribute :owner, ::VOCABULARY[:jupiter_core].owner, solrize_for: [:exact_match]
          end
          unless attribute_names.include?(:record_created_at)
            has_attribute :record_created_at, ::VOCABULARY[:jupiter_core].record_created_at, type: :date,
                                                                                             solrize_for: [:sort]
          end
        end
      end

      def remote_object_includes(module_name)
        derived_af_class.send(:include, module_name)
      end

      def derived_af_class_name
        return AF_CLASS_PREFIX + to_s if name.present?
        "AnonymousDerivedClass#{object_id}"
      end

      def when_writable(&block)
        derived_af_class.class_eval(&block)
      end

      # for a class Book, this would generate an ActiveFedora subclass "IRBook"
      def generate_af_class
        if const_defined? derived_af_class_name
          raise AlreadyDefinedError, "The attempted ActiveFedora class generation name '#{derived_af_class_name}' is"\
                                     'already defined'
        end
        self.af_parent_class ||= ActiveFedora::Base

        af_class = Class.new(self.af_parent_class) do
          attr_accessor :owning_object

          validate :visibility_must_be_known
          validates :owner, presence: true
          validates :record_created_at, presence: true

          before_validation :set_record_created_at, on: :create

          # ActiveFedora gives us system_create_dtsi, but that only exists in Solr, because what everyone wants
          # is a created_at that jumps around when you rebuild your index
          def set_record_created_at
            self.record_created_at = Time.current.utc.iso8601(3)
          end

          def visibility_must_be_known
            return true if visibility.present? && owning_object.class.valid_visibilities.include?(visibility)
            errors.add(:visibility, "#{visibility} is not a known visibility")
          end

          # Paper over a 2 year old bug in ActiveFedora where it simply SILENTLY IGNORES validation callbacks
          # (https://github.com/samvera/active_fedora/issues/914)
          # ...
          # don't try to write your own ORM, kids
          def run_validations!
            run_callbacks(:validation) do
              super
            end
          end

          def owning_class
            self.class.owning_class
          end

          class << self

            attr_reader :owning_class

          end

          # a single common indexer for all subclasses which leverages stored property metadata to DRY up indexing
          def self.indexer
            JupiterCore::Indexer
          end

          # Methods defined on the +owning_object+ can be called by the "unlocked" methods defined on the ActiveFedora
          # object
          def method_missing(name, *args, &block)
            return owning_object.send(name, *args, &block) if owning_object.respond_to?(name, true)
            super
          end

          def respond_to_missing?(name, include_private = false)
            owning_object.respond_to?(name, include_private) || super
          end
        end

        af_class.instance_variable_set(:@owning_class, self)
        Object.const_set(derived_af_class_name, af_class)
        self.af_parent_class = af_class
        af_class
      end

      def derived_af_class
        @derived_af_class ||= generate_af_class
      end

      # Write properties directly to the solr index for an LDP object, without having to back them in the LDP
      # a lambda, +as+, controls how it is calculated.
      # Examples:
      #
      #    solr_index :downcased_title, solrize_for: :exact_match, as: -> { title.downcase }
      #
      def solr_index(name, solrize_for:, as:)
        raise PropertyInvalidError unless as.respond_to?(:call)
        raise PropertyInvalidError unless name.present?
        raise PropertyInvalidError unless solrize_for.present? && solrize_for.is_a?(Symbol)

        self.solr_calc_attributes ||= {}
        self.solr_calc_attributes[name] = { type: SOLR_DESCRIPTOR_MAP[solrize_for], callable: as }
      end

      def has_multival_attribute(name, predicate, solrize_for: [], type: :string)
        has_attribute(name, predicate, multiple: true, solrize_for: solrize_for, type: type)
      end

      # a utility DSL for declaring attributes which allows us to store knowledge of them.
      def has_attribute(name, predicate, multiple: false, solrize_for: [], type: :string)
        raise PropertyInvalidError unless name.is_a? Symbol
        raise PropertyInvalidError unless predicate.present?

        # TODO: keep this conveinience, or push responsibility for [] onto the callsite?
        solrize_for = [solrize_for] unless solrize_for.is_a? Array

        # index should contain only some combination of :search, :sort, :facet, :symbol, and :path
        # this isn't an exhaustive layering over this mess
        # https://github.com/mbarnett/solrizer/blob/e5dd2bd571b9ebdb8a8ab214574075c28951e53e/lib/solrizer/default_descriptors.rb
        # but it helps
        raise PropertyInvalidError if solrize_for.count { |item| !SOLR_DESCRIPTOR_MAP.keys.include?(item) } > 0

        # TODO: type validation

        attribute_names << name

        solr_name_cache ||= []
        solrize_for.each do |descriptor|
          solr_name = Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[descriptor], type: type)
          solr_name_cache << solr_name
          reverse_solr_name_cache[solr_name] = name
        end

        facets << Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:facet], type: type) if solrize_for.include?(:facet)
        facets << Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:path], type: type) if solrize_for.include?(:path)

        attribute_cache[name] = {
          predicate: predicate,
          multiple: multiple,
          solrize_for: solrize_for,
          type: type,
          solr_names: solr_name_cache
        }

        define_method name do
          val = if remote_object.present?
                  remote_object.send(name)
                else
                  solr_representation[solr_name_cache.first]
                end
          return if val.nil?
          return DateTime.parse(val).freeze if type == :date
          return val.freeze if val.nil? || multiple || !val.is_a?(Array)
          return val.first.freeze
        end

        define_method "#{name}=" do |*_args|
          raise LockedInstanceError, 'The Locked LDP object cannot be mutated outside of an unlocked block or without'\
                                     'calling flush_cache_and_perform_remote_write to load a writable copy (SLOW).'
        end

        derived_af_class.class_eval do
          property name, predicate: predicate, multiple: multiple do |index|
            index.type type if type.present?
            index.as(*(solrize_for.map { |idx| SOLR_DESCRIPTOR_MAP[idx] }))
          end
        end
      end

    end

  end
end
