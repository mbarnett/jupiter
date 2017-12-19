# JupiterCore::LockedLdpObject classes are lightweight, read-only objects
# TODO: this file could benefit from some reorganization, possibly into several files
module JupiterCore
  class ObjectNotFound < StandardError; end
  class PropertyInvalidError < StandardError; end
  class MultipleIdViolationError < StandardError; end
  class AlreadyDefinedError < StandardError; end
  class LockedInstanceError < StandardError; end

  VISIBILITY_PUBLIC = CONTROLLED_VOCABULARIES[:visibility].public.freeze
  VISIBILITY_PRIVATE = CONTROLLED_VOCABULARIES[:visibility].private.freeze
  VISIBILITY_AUTHENTICATED = CONTROLLED_VOCABULARIES[:visibility].authenticated.freeze

  VISIBILITIES = [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE, VISIBILITY_AUTHENTICATED].freeze

  class LockedLdpObject

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

    # we reserve .new for internal use in constructing LockedLDPObjects. Use the public interface
    # +new_locked_ldp_object+ for constructing new objects externally.
    private_class_method :new

    # inheritable class attributes (not all class-level attributes in this class should be inherited,
    # these are the inheritance-safe attributes)
    class_attribute :af_parent_class, :attribute_cache, :attribute_names, :facets,
                    :association_indexes, :reverse_solr_name_cache, :solr_calc_attributes

    # Returns the id of the object in LDP as a String
    def id
      return ldp_object.send(:id) if ldp_object.present?
      solr_representation['id'] if solr_representation
    end

    # Provides structured, mediated interaction for mutating the underlying LDP object
    #
    # yields the underlying mutable +ActiveFedora+ object to the block and returns self for chaining
    #
    #  locked_obj.unlock_and_fetch_ldp_object do |ldp_object|
    #    ldp_object.title = 'asdf'
    #    ldp_object.save
    #  end
    def unlock_and_fetch_ldp_object
      self.ldp_object = self.class.send(:derived_af_class).find(self.id) if @ldp_object.blank?
      yield @ldp_object
      self
    end

    # Returns name-value pairs for all of the LDP Object's attributes as a Hash
    def attributes
      self.class.attribute_names.map do |name|
        [name.to_s, self.send(name)]
      end.to_h
    end

    # Returns name-value pairs for the LDP Object's attributes named by +display_attribute_names+ as a Hash
    def display_attributes
      self.class.display_attribute_names.map do |name|
        [name.to_s, self.send(name)]
      end.to_h
    end

    # A better debug representation for LDP Objects
    def inspect
      attrs = self.class.attribute_names + self.class.association_indexes
      debugstr = attrs.map do |name|
        val = self.send(name)
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
      end
      "#<#{self.class.name || 'AnonymousClass'} " + debugstr.join(', ') + '>'
    end

    # Has this object been persisted? (Defined for ActiveModel compatibility)
    def persisted?
      # if we haven't had to load the internal ldp_object, by definition we must by synced to disk
      return true if ldp_object.blank?
      ldp_object.persisted?
    end

    # Has this object been changed since being loaded? (Defined for ActiveModel compatibility)
    def changed?
      return false if ldp_object.blank?
      ldp_object.changed?
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def valid?(*args)
      return super(*args) if ldp_object.blank?
      ldp_object.valid?(*args)
    end

    # Do this object's validations pass? (Defined for ActiveModel compatibility)
    def errors
      return super if ldp_object.blank?
      ldp_object.errors
    end

    # Derives a solr-formatted (mangled_attr_name: value) search term for an instance's attribute.
    # eg)
    #    obj.search_term_for(:title)
    #    => "title_tesim:\"The effects of Celebrator Doppelbock on cats\""
    def search_term_for(attr_name)
      self.class.search_term_for(attr_name, self.send(attr_name))
    end

    def read_solr_index(name)
      raise PropertyInvalidError unless name.is_a? Symbol
      type_info = self.solr_calc_attributes[name]
      raise PropertyInvalidError if type_info.blank?
      solr_representation[type_info[:solr_names].first]
    end

    # Use this to create a new +LockedLDPObjects+ and its underlying LDP instance. attrs populate the new object's
    # attributes
    def self.new_locked_ldp_object(*attrs)
      new(ldp_obj: derived_af_class.new(*attrs))
    end

    # Override this in your subclasses to control what attributes are automatically listed in the attributes list
    def self.display_attribute_names
      self.attribute_names - [:id]
    end

    # An array of attribute names that are safe to be used for safe_params calls in controllers. ID is _never_ a safe
    # attribute for forms to modify. Subclasses should override this and remove any other sensitive attributes from
    # this array
    #
    # a Item +LockedLDPObject+ might choose to protect its +owner+ attribute by overriding this method:
    #
    #  def self.safe_attributes
    #    super - [:owner]
    #  end
    #
    # and then enforce that in a controller like items_controller.rb:
    #    def item_params
    #      params[:item].permit(Item.safe_attributes)
    #    end
    def self.safe_attributes
      self.attribute_names - [:id]
    end

    # Accepts a symbol representing the attribute name, and returns a Hash containing
    # metadata about an object's attributes.
    #
    # Given a subclass +Item+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then the Hash returned by <tt>Item.attribute_metadata(:title)</tt> would be:
    #   {
    #      :predicate => #<RDF::Vocabulary::Term:0x3fe32a1d1a30 URI:http://purl.org/dc/terms/title>,
    #      :multiple => false,
    #      :solrize_for => [:search, :facet],
    #      :type => :string,
    #      :solr_names => ["title_tesim", "title_sim"]
    #   }
    def self.attribute_metadata(attribute_name)
      self.attribute_cache[attribute_name]
    end

    # Accepts a String name of a name-mangled solr field, and returns the symbol of the attribute that corresponds to it
    #
    # Given a subclass +Item+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then:
    #   Item.solr_name_to_attribute_name('title_tesim')
    #   => :title
    def self.solr_name_to_attribute_name(solr_name)
      self.reverse_solr_name_cache[solr_name]
    end

    # Accepts the symbolic name of an attribute, and the "solrize_for" role, and returns the string
    # representing the mangled solr name for that role. eg)
    #
    # Given a subclass +Item+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then:
    #   Item.solr_name_for(:title, role: :search)
    #   => "title_tesim"
    def self.solr_name_for(attribute_name, role:)
      attribute_metadata = self.attribute_cache[attribute_name]
      if attribute_metadata.present?
        sort_attr_index = attribute_metadata[:solrize_for].index(role)
        raise ArgumentError, "No #{role} solr role is defined for #{attribute_name}" if sort_attr_index.blank?
        return attribute_metadata[:solr_names][sort_attr_index]
      else
        solr_metadata = self.solr_calc_attributes[attribute_name]
        raise ArgumentError, "No such attribute is defined, #{attribute_name}" if solr_metadata.blank?
        solrize_for = solr_metadata[:solrize_for]
        idx = solrize_for.find_index(role)
        raise ArgumentError, "#{attribute_name} not indexed for #{role}" if idx.blank?
        return solr_metadata[:solr_names][idx]
      end
    end

    # Accepts the symbolic name of an attribute, and a value to search for, and returns the string
    # representing the solr search term. eg)
    #
    # Given a subclass +Item+ with an attribute declaration:
    #   has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet]
    #
    # then:
    #   Item.search_term_for(:title, 'science')
    #   => "title_tesim:science"
    def self.search_term_for(attr_name, value, role: :search)
      rails ArgumentError("search value can't be nil") if value.nil?
      solr_attr_name = solr_name_for(attr_name, role: role)
      %Q(#{solr_attr_name}:"#{value}")
    end

    # Accepts a string id of an object in the LDP, and returns a +LockedLDPObjects+ representation of that object
    # or raises <tt>JupiterCore::ObjectNotFound</tt> if there is no object corresponding to that id
    def self.find(id)
      results_count, results, _ = JupiterCore::Search.perform_solr_query(q: %Q(_query_:"{!raw f=id}#{id}"),
                                                                         restrict_to_model: derived_af_class)

      raise ObjectNotFound, "Couldn't find #{self} with id='#{id}'" if results_count == 0
      raise MultipleIdViolationError if results_count > 1

      new(solr_doc: results.first)
    end

    # find with "return nil if no object with that ID is found" semantics
    # Note: This behaves differently then AR find_by.
    # As it can only take a single argument which is an ID (which is a limitation from ActiveFedora)
    def self.find_by(id)
      self.find(id)
    rescue ObjectNotFound
      return nil
    end

    # Returns an array of all +LockedLDPObject+ in the LDP
    # def self.all(limit:, offset: )
    def self.all
      JupiterCore::DeferredSimpleSolrQuery.new(self)
    end

    # Integer, the number of records in Solr/Fedora
    def self.count
      all.count
    end

    # Accepts a hash of name-value pairs to query for, and returns an Array of matching +LockedLDPObject+
    #
    # For example:
    #   Item.where(title: 'Test upload')
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
    #    => {<lots of solr garbage>}
    #    2.4.0 :004 > JupiterCore::LockedLdpObject.reify_solr_doc(solr_doc)
    #    => #<Item id: "88489b6e-12dd-4eea-b833-af08782c419e", <other properties>>  #
    def self.reify_solr_doc(solr_doc)
      raise ArgumentError, 'Not a valid LockedLDPObject representation' if solr_doc['has_model_ssim'].blank?
      solr_doc['has_model_ssim'].first.constantize.owning_class.send(:new, solr_doc: solr_doc)
    end

    private

    attr_reader :ldp_object
    attr_accessor :solr_representation

    def initialize(solr_doc: nil, ldp_obj: nil)
      raise ArgumentError if solr_doc.present? && ldp_obj.present?
      self.solr_representation = solr_doc if solr_doc.present?
      self.ldp_object = ldp_obj if ldp_obj.present?
    end

    def method_missing(name, *args, &block)
      return super unless self.class.send(:derived_af_class).instance_methods.include?(name)
      raise LockedInstanceError, 'This is a locked cache instance and does not respond to the method you attempted '\
                                 "to call (##{name}). However, the locked instance DOES respond to ##{name}. Use "\
                                 'unlock_and_fetch_ldp_object to load a writable copy (SLOW).'
    end

    # Looks pointless, but keeps rubocop happy because of the error-message refining +method_missing+ above
    def respond_to_missing?(*_args); super; end

    def ldp_object=(obj)
      @ldp_object = obj
      @ldp_object.owning_object = self

      # NOTE: it's important to establish the owning object PRIOR to calling to_solr, as solr_calc_properties
      # could need to call methods that get forwarded to the owning object
      @solr_representation = @ldp_object.to_solr

      @ldp_object
    end

    def coerce_value(value, to:)
      return nil if value.nil?
      case to
      when :string, :text
        value.to_s
      when :bool
        value
      when :int
        value.to_i
      when :float
        value.to_f
      when :path
        value
      when :date
        if value.is_a?(String)
          Time.zone.parse(value)
        elsif value.is_a?(DateTime)
          value
        elsif value.is_a?(Date) || value.is_a?(Time)
          Time.zone.parse(value)
        end
      else
        raise TypeError, "Unknown coercion type: #{type}"
      end
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
        child.attribute_names = self.attribute_names ? self.attribute_names.dup : [:id]
        child.reverse_solr_name_cache = self.reverse_solr_name_cache ? self.reverse_solr_name_cache.dup : {}
        child.attribute_cache = self.attribute_cache ? self.attribute_cache.dup : {}
        child.facets = self.facets ? self.facets.dup : []
        child.solr_calc_attributes = self.solr_calc_attributes.present? ? self.solr_calc_attributes.dup : {}
        child.association_indexes = self.association_indexes.present? ? self.association_indexes.dup : []
        # If there's no class between +LockedLdpObject+ and this child that's
        # already had +visibility+ and +owner+ defined, define them.
        child.class_eval do
          unless attribute_names.include?(:visibility)
            has_attribute :visibility, ::RDF::Vocab::DC.accessRights, solrize_for: [:exact_match, :facet]
          end
          unless attribute_names.include?(:owner)
            has_attribute :owner, ::TERMS[:bibo].owner, type: :int, solrize_for: [:exact_match]
          end
          unless attribute_names.include?(:record_created_at)
            has_attribute :record_created_at, ::TERMS[:jupiter_core].record_created_at, type: :date,
                                                                                        solrize_for: [:sort]
          end
        end
      end

      def ldp_object_includes(module_name)
        derived_af_class.send(:include, module_name)
      end

      def derived_af_class_name
        return AF_CLASS_PREFIX + self.to_s if self.name.present?
        "AnonymousDerivedClass#{self.object_id}"
      end

      def unlocked(&block)
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
            errors.add(:visibility, I18n.t('locked_ldp_object.errors.invalid_visibility', visibility: visibility))
          end

          # this is the nice version of coerce_value. This is used for data going _in_ to Fedora/Solr, so it
          # sanity checks the conversion. coerce_value blindly does the conversion, for assumed-good data being
          # read back from Fedora/Solr
          def convert_value(value, to:)
            return value if value.nil?
            case to
            when :string, :text
              unless value.is_a?(String)
                raise TypeError, "#{value} isn't a String. Call to_s explicitly if "\
                                 "that's what you want"
              end
              value
            when :date
              # ActiveFedora/RDF does the wrong thing with Time (see below) AND
              # it serializes every other Date type to a string internally at a very low precision (second granularity)
              # so we convert all date types into strings ourselves to bypass ActiveFedora's serialization, and then
              # use our modifications to Solrizer to save them in solr in a proper date index.
              value = value.to_datetime if value.is_a?(Date)
              if value.is_a?(String)
                value
              elsif value.respond_to?(:iso8601)
                value.utc.iso8601(3)
              else
                raise TypeError, "#{value} is not a Date type"
              end
            when :bool
              raise TyperError, "#{value} is not a boolean" unless [true, false].include?(value)
              value
            when :int
              raise TypeError, "#{value} is not a integer value" unless value.is_a?(Integer)
              value
            when :path
              value
            when :float
              raise TypeError, "#{value} is not a float value" unless value.is_a?(Float)
              value
            else
              raise 'NOT IMPLEMENTED'
            end
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

          def self.owning_class
            @owning_class
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

      # add a method to the +LockedLdpObject that reads from the solr representation or defers to the ldp_object
      # if one is present. Allows for the specification of a "specialized ldp reader", a lambda mostly intended
      # for use when reading associations on the AF object that have been given a better name when hoisted
      def define_cached_reader(name, multiple:, type:, canonical_solr_name:, specialized_ldp_reader: nil)
        define_method name do
          val = if ldp_object.present?
                  if specialized_ldp_reader.present?
                    ldp_object.instance_exec(&specialized_ldp_reader)
                  else
                    ldp_object.send(name)
                  end
                else
                  solr_representation[canonical_solr_name]
                end
          return if val.nil?
          val = val.first if val.is_a?(Array) && !multiple
          return coerce_value(val, to: type).freeze unless multiple
          coerced_values = val.map do |v|
            coerce_value(v, to: type).freeze
          end
          return coerced_values.freeze
        end
      end

      # Write properties directly to the solr index for an LDP object, without having to back them in the LDP
      # a lambda, +as+, controls how it is calculated.
      # Examples:
      #
      #    additional_search_index :downcased_title, solrize_for: :exact_match, as: -> { title.downcase }
      #
      def additional_search_index(name, solrize_for:, type: :symbol, as:)
        raise PropertyInvalidError unless as.respond_to?(:call)
        raise PropertyInvalidError if name.blank?
        raise PropertyInvalidError unless type.present? && type.is_a?(Symbol)
        solrize_for = [solrize_for] unless solrize_for.is_a?(Array)

        solr_descriptors = []
        solr_names = []
        solrize_for.each do |solr_role|
          descriptor = SOLR_DESCRIPTOR_MAP[solr_role]
          solr_name = Solrizer.solr_name(name, descriptor, type: type)
          solr_names << solr_name
          self.reverse_solr_name_cache[solr_name] = name
          self.facets << solr_name if solr_role == :facet
          solr_descriptors << descriptor
        end

        self.solr_calc_attributes[name] = { type: type,
                                            solrize_for: solrize_for,
                                            solr_descriptors: solr_descriptors,
                                            solr_names: solr_names,
                                            callable: as }
      end

      def belongs_to(name, using_existing_association:)
        index_and_hoist_existing_association(using_existing_association, as_name: name, multiple: false)
      end

      def has_many(name, using_existing_association:)
        index_and_hoist_existing_association(using_existing_association, as_name: name, multiple: true)
      end

      def has_one(name, using_existing_association:)
        index_and_hoist_existing_association(using_existing_association, as_name: name, multiple: false)
      end

      def index_and_hoist_existing_association(association, as_name:, multiple:)
        association_names = derived_af_class.reflect_on_all_associations.keys
        raise ArgumentError, 'No such association' unless association_names.include? association
        raise ArgumentError, 'Invalid association' if derived_af_class.reflect_on_all_associations[association].is_a?(
          ActiveFedora::Reflection::HasSubresourceReflection
        )

        # Add to cache for use in queries
        self.attribute_cache[as_name] = {
          predicate: nil,
          multiple: multiple,
          solrize_for: [:search],
          type: :string,
          solr_names: [Solrizer.solr_name(as_name, SOLR_DESCRIPTOR_MAP[:search], type: :string)]
        }

        self.association_indexes ||= []
        self.association_indexes << as_name

        # Get association ids into solr
        additional_search_index as_name, solrize_for: :search,
                                         as: lambda {
                                               self.send(association)&.map do |member|
                                                 member.id
                                               end
                                             }
        # add a reader to the locked object
        define_cached_reader(as_name, multiple: multiple, type: :string,
                                      canonical_solr_name: Solrizer.solr_name(as_name,
                                                                              SOLR_DESCRIPTOR_MAP[:search],
                                                                              type: :string),
                                      specialized_ldp_reader: lambda {
                                                                self.send(association)&.map do |member|
                                                                  member.id
                                                                end
                                                              })

        # let people use the "better name" when unlocked, for sheer sanity
        # eg. if you index the awful "member_of_collections" as "member_of_works" on FileSet to better reflect that it
        # has nothing whatsoever to do with collections, let people use and assign to that when unlocked
        # this also simplifies functioning of method forwarding between the locked and unlocked object
        # as that generally assumes that "attribute" names are identically named on both objects

        # TODO: this block could reaaaaally use some consolidation.
        if multiple
          derived_af_class.class_eval do
            alias_method(as_name, association) if association != as_name
            define_method "#{as_name}=" do |args|
              args = args.map do |arg|
                arg.is_a?(LockedLdpObject) ? arg.send(:ldp_object) : arg
              end

              self.send("#{association}=", args)
            end
          end
        else
          derived_af_class.class_eval do
            define_method as_name do
              self.send(association).first
            end
            define_method "#{as_name}=" do |arg|
              arg = arg.send(:ldp_object) if arg.is_a?(LockedLdpObject)
              self.send("#{association}=", [arg])
            end
          end
        end
      end

      def has_multival_attribute(name, predicate, solrize_for: [], type: :string)
        has_attribute(name, predicate, multiple: true, solrize_for: solrize_for, type: type)
      end

      # a utility DSL for declaring attributes which allows us to store knowledge of them.
      def has_attribute(name, predicate, multiple: false, solrize_for: [], type: :string)
        raise PropertyInvalidError unless name.is_a? Symbol
        raise PropertyInvalidError if predicate.blank?
        raise PropertyInvalidError if solrize_for.blank?

        # TODO: keep this conveinience, or push responsibility for [] onto the callsite?
        solrize_for = [solrize_for] unless solrize_for.is_a? Array

        # index should contain only some combination of :search, :sort, :facet, :symbol, and :pathing
        # this isn't an exhaustive layering over this mess
        # https://github.com/mbarnett/solrizer/blob/e5dd2bd571b9ebdb8a8ab214574075c28951e53e/lib/solrizer/default_descriptors.rb
        # but it helps
        raise PropertyInvalidError if solrize_for.count { |item| !SOLR_DESCRIPTOR_MAP.keys.include?(item) } > 0

        raise PropertyInvalidError, "Unknown type #{type}" unless [:string, :text, :path, :bool, :date, :int,
                                                                   :float].include?(type)

        self.attribute_names << name

        solr_name_cache ||= []
        solrize_for.each do |descriptor|
          solr_name = Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[descriptor], type: type)
          solr_name_cache << solr_name
          self.reverse_solr_name_cache[solr_name] = name
        end

        facet_name = if solrize_for.include?(:facet)
                       Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:facet], type: type)
                     elsif solrize_for.include?(:pathing)
                       Solrizer.solr_name(name, SOLR_DESCRIPTOR_MAP[:pathing], type: type)
                     end

        self.facets << facet_name if facet_name.present?

        self.attribute_cache[name] = {
          predicate: predicate,
          multiple: multiple,
          solrize_for: solrize_for,
          type: type,
          solr_names: solr_name_cache
        }

        # define the read-only attribute method for the locked object
        #
        # TODO: right now the "canonical solr name" is the solr name we use for the value retrived by the reader method
        # ie. if you have title_tesim, title_sim, title_ssi etc in your solr document, the canonical_solr_name is one
        # of those, and its that key's value that the +title+ method returns. Right now we use the first +solrize_for+
        # value as the "canonical solr name", but it should probably be selected more intelligently, somehow, by, say
        # prefering :sort, or something.
        define_cached_reader(name, multiple: multiple, type: type, canonical_solr_name: solr_name_cache.first)

        define_method "#{name}=" do |*_args|
          raise LockedInstanceError, 'The Locked LDP object cannot be mutated outside of an unlocked block or without'\
                                     'calling unlock_and_fetch_ldp_object to load a writable copy (SLOW).'
        end

        derived_af_class.class_eval do
          property name, predicate: predicate, multiple: multiple do |index|
            index.type type if type.present?
            index.as(*(solrize_for.map { |idx| SOLR_DESCRIPTOR_MAP[idx] }))
          end
        end

        # A thrilling tale of Yet Another Community Bug™
        #
        # Suppose you have an ActiveFedora class, Item, with a property, embargo_date, type: date.
        #
        #    item.embargo_date = Time.now + 20.years
        #    => #<Item id: "829ad1b6-c54d-460f-a3c5-6dd716464f06", embargo_date: 2037-09-15T15:59:58.724Z>
        #
        # Looks good!
        #
        #    item.save
        #    => true
        #    item
        #    => #<Item id: "829ad1b6-c54d-460f-a3c5-6dd716464f06", embargo_date: 2017-09-15T22:05:15.000Z>
        #
        # WHAT JUST HAPPENED TO OUR EMBARGO DATE?!
        #
        # We verified that the date was correct in the item, until we saved, at which IT SILENTLY BECAME TODAY (!!!!)
        #
        # Dive about 30 layers deep into the call stack, and you'll eventually discover that this happens because:
        #
        # 1) ActiveFedora pretty much ignores declared types and just slings around whatever an object happens to be
        # after assignment, type declarations on properties be damned.
        #
        # Combined with:
        #
        # 2)
        #    (Time.now + 20.years).class
        #    => Time
        #
        # 3) a 7 year old bug in the RDF gem (https://github.com/ruby-rdf/rdf/blob/d7add8de9ce12c10192eaadb654fa5adc1a66277/lib/rdf/model/literal.rb#L123)
        # based on the erroneous assumption that they can treat the Ruby Time class as representing a time-of-day
        # independent of date, despite this never having ever been remotely true of the Ruby Time class, which
        # represents seconds since the UNIX epoch, and thus has always _fundamentally_ represented a specific date AND
        # time, despite the comment on that code suggesting that this is some kind of odd and unexpected corner case.
        #
        # I don't think that anyone would claim that this kind of silent, destructive data-loss "works as intended", or
        # represents sane and safe API design, but at this point the semantics of all of the above, however poorly
        # thought out, appear to be deeply entrenched in a lot of people's code in a lot of projects, and I don't see
        # a way to fix that other than breaking a lot of years-old assumptions and refactoring the way ActiveFedora,
        # Solrizer, ActiveTriples, and RDF (fail to) talk to one another -- so the cleanest and easiest way to fix this
        # appears to be to paper over it all on our end.
        #
        # Prior to discovering this mess, we just let the ActiveFedora property declartion in the derived AF class
        # create the setters on the unlocked object. Now, we're going to shadow all of ActiveFedora's property
        # setters, coerce the argument to the declared type or complain if that burden should fall on the caller, and
        # then pass it along to ActiveFedora, in the hope that this way we can limit the opportunities for the rest
        # of the stack to silently do the wrong thing by confining ourselves to types where the behaviour (so far)
        # seems moderately sane.
        #
        # (ﾉಥ益ಥ）ﾉ﻿ ┻━┻
        derived_af_class.class_eval do
          # alias AF assignment method
          alias_method :"shadowed_assign_#{name}", :"#{name}="

          define_method "#{name}=" do |arg|
            converted_arg = if arg.is_a?(Array)
                              arg.map { |val| convert_value(val, to: type) }
                            else
                              convert_value(arg, to: type)
                            end
            # call the shadowed AF assignment method
            self.send("shadowed_assign_#{name}", converted_arg)
          end
        end
      end

    end

  end
end
