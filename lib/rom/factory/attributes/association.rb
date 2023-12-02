# frozen_string_literal: true

module ROM::Factory
  module Attributes
    # @api private
    # rubocop:disable Style/OptionalArguments
    module Association
      class << self
        def new(assoc, builder, *traits, **options)
          const_get(assoc.definition.type).new(assoc, builder, *traits, **options)
        end
      end

      # @api private
      class Core
        attr_reader :assoc, :options, :traits

        # @api private
        def initialize(assoc, builder, *traits, **options)
          @assoc = assoc
          @builder_proc = builder
          @traits = traits
          @options = options
        end

        # @api private
        def through?
          false
        end

        # @api private
        def builder
          @__builder__ ||= @builder_proc.call
        end

        # @api private
        def name
          assoc.key
        end

        # @api private
        def dependency?(*)
          false
        end

        # @api private
        def value?
          false
        end

        # @api private
        def factories
          builder.factories
        end

        # @api private
        def foreign_key
          assoc.foreign_key
        end

        # @api private
        def count
          options.fetch(:count, 1)
        end
      end

      # @api private
      class ManyToOne < Core
        # @api private
        # rubocop:disable Metrics/AbcSize
        def call(attrs, persist: true)
          return if attrs.key?(name) && attrs[name].nil?

          assoc_data = attrs.fetch(name, EMPTY_HASH)

          if assoc_data.is_a?(Hash) && assoc_data[assoc.target.primary_key] && !attrs[foreign_key]
            assoc.associate(attrs, attrs[name])
          elsif assoc_data.is_a?(ROM::Struct)
            assoc.associate(attrs, assoc_data)
          elsif !attrs[foreign_key]
            parent = if persist
                       builder.persistable.create(*parent_traits, **assoc_data)
                     else
                       builder.struct(*parent_traits, **assoc_data)
                     end

            tuple = {name => parent}

            assoc.associate(tuple, parent)
          end
        end
        # rubocop:enable Metrics/AbcSize

        private

        def parent_traits
          @parent_traits ||=
            if assoc.target.associations.key?(assoc.source.name)
              traits + [assoc.target.associations[assoc.source.name].name => false]
            else
              traits
            end
        end
      end

      # @api private
      class OneToMany < Core
        # @api private
        def call(attrs = EMPTY_HASH, parent, persist: true)
          return if attrs.key?(name)

          structs = Array.new(count).map do
            # hash which contains the foreign key info, i.e: { user_id: 1 }
            association_hash = assoc.associate(attrs, parent)

            if persist
              builder.persistable.create(*traits, **association_hash)
            else
              builder.struct(*traits, **attrs, **association_hash)
            end
          end

          {name => structs}
        end

        # @api private
        def dependency?(rel)
          assoc.source == rel
        end
      end

      # @api private
      class OneToOne < OneToMany
        # @api private
        def call(attrs = EMPTY_HASH, parent, persist: true)
          # do not associate if count is 0
          return {name => nil} if count.zero?

          return if attrs.key?(name)

          association_hash = assoc.associate(attrs, parent)

          struct = if persist
                     builder.persistable.create(*traits, **association_hash)
                   else
                     belongs_to_name = Dry::Core::Inflector.singularize(assoc.source_alias)
                     belongs_to_associations = {belongs_to_name.to_sym => parent}
                     final_attrs = attrs.merge(association_hash).merge(belongs_to_associations)
                     builder.struct(*traits, **final_attrs)
                   end

          {name => struct}
        end
      end

      class ManyToMany < Core
        def call(attrs = EMPTY_HASH, parent, persist: true)
          return if attrs.key?(name)

          structs = count.times.map do
            if persist && attrs[tpk]
              attrs
            elsif persist
              builder.persistable.create(*traits, **attrs)
            else
              builder.struct(*traits, **attrs)
            end
          end

          # Delegate to through factory if it exists
          if persist
            if through_factory?
              structs.each do |child|
                through_attrs = {
                  Dry::Core::Inflector.singularize(assoc.source.name.key).to_sym => parent,
                  assoc.through.assoc_name => child
                }

                factories[through_factory_name, **through_attrs]
              end
            else
              assoc.persist([parent], structs)
            end

            {name => result(structs)}
          else
            result(structs)
          end
        end

        def result(structs)
          {name => structs}
        end

        def dependency?(rel)
          assoc.source == rel
        end

        def through?
          true
        end

        def through_factory?
          factories.registry.key?(through_factory_name)
        end

        def through_factory_name
          ROM::Inflector.singularize(assoc.definition.through.source).to_sym
        end

        private

        def tpk
          assoc.target.primary_key
        end
      end

      class OneToOneThrough < ManyToMany
        def result(structs)
          {name => structs[0]}
        end
      end
    end
  end
  # rubocop:enable Style/OptionalArguments
end
