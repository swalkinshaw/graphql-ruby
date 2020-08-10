# frozen_string_literal: true
module GraphQL
  module StaticValidation
    module FieldsWillMergeNew
      # Validates that a selection set is valid if all fields (including spreading any
      # fragments) either correspond to distinct response names or can be merged
      # without ambiguity.
      #
      class FieldSetCache
        attr_reader :cache, :context

        def initialize(fields, cache:, context:)
          @fields = fields
          @cache = cache
          @context = context

          @cache_group_by_output_names = nil
          @cache_group_by_common_parent_types = nil
          @cache_merge_child_selections = nil

          @required_same_response_shape = false
          @required_same_name_and_arguments = false
          @checked_same_response_shape = false
          @checked_same_fields_for_coincident_parent_types = false
        end

        def fields_in_set_can_merge?
          same_response_shape?
          same_fields_for_coincident_parent_types?
        end

        def same_response_shape?
          return if @checked_same_response_shape if @checked_same_response_shape
          @checked_same_response_shape = true

          group_selections_by_output_name.each do |field_set|
            field_set.require_same_response_shape
            merged_set = field_set.merge_child_selections
            merged_set.same_response_shape?
          end
        end

        def same_fields_for_coincident_parent_types?
          return if @checked_same_fields_for_coincident_parent_types if @checked_same_fields_for_coincident_parent_types
          @checked_same_fields_for_coincident_parent_types = true

          group_selections_by_output_name.each do |field_set|
            field_set.group_by_common_parent_types.each do |set|
              set
                .require_same_name_and_arguments
                .merge_child_selections
                .same_fields_for_coincident_parent_types?
            end
          end
        end

        def group_selections_by_output_name
          return @cache_group_by_output_names if @cache_group_by_output_names

          @fields.group_by(&:output_name).values.map do |fields|
            cache[fields]
          end
        end

        def group_by_common_parent_types
          return @cache_group_by_common_parent_types if @cache_group_by_common_parent_types

          abstract, concrete = @fields.partition(&:parent_type_abstract?)
          concrete_groups = concrete.group_by { |field| field.parent_type_definition.name }

          @cache_group_by_common_parent_types = combine_abstract_and_concrete_parent_types(
            abstract, concrete_groups
          )
        end

        def require_same_response_shape
          return self if @require_same_response_shape
          @require_same_response_shape = true

          grouped = group_by_known_response_shape.values.flatten
          output_name = grouped[0].output_name

          grouped.each_cons(2) do |a, b|
            check_conflict(output_name, a, b)
          end

          self
        end

        def require_same_name_and_arguments
          return self if @required_same_name_and_arguments
          @required_same_name_and_arguments = true

          grouped = group_by_field_name_and_arguments.values.flatten
          output_name = grouped[0].output_name

          grouped.each_cons(2) do |a, b|
            check_conflict(output_name, a, b)
          end

          self
        end

        def group_by_known_response_shape
          @fields.group_by(&:type_shape)
        end

        def group_by_field_name_and_arguments
          @fields.group_by(&:name_and_arguments)
        end

        def check_conflict(response_key, field1, field2)
          node1 = field1.node
          node2 = field2.node

          type1 = field1.type
          type2 = field2.type

          # if check_list_and_non_null_conflict(response_key, field1, field2)
          # end

          type1 = type1.unwrap
          type2 = type2.unwrap

          if type1.kind.scalar? && type2.kind.scalar?
            if type1.kind != type2.kind
              context.errors << GraphQL::StaticValidation::FieldsWillMergeError.new(
                "TODO diff scalar types",
                nodes: [node1, node2],
                path: [],
                field_name: response_key,
                conflicts: ["TODO"]
              )

              return
            end
          end

          if type1.kind.enum? && type2.kind.enum?
            if type1.kind != type2.kind
              context.errors << GraphQL::StaticValidation::FieldsWillMergeError.new(
                "TODO diff enum types",
                nodes: [node1, node2],
                path: [],
                field_name: response_key,
                conflicts: ["TODO"]
              )

              return
            end
          end

          if field1.parent_type_definition != field2.parent_type_definition &&
            field1.parent_type_definition.kind.object? &&
            field2.parent_type_definition.kind.object?

            return
          end

          if node1.name != node2.name
            errored_nodes = [node1.name, node2.name].sort.join(" or ")
            msg = "Field '#{response_key}' has a field conflict: #{errored_nodes}?"

            context.errors << GraphQL::StaticValidation::FieldsWillMergeError.new(
              msg,
              nodes: [node1, node2],
              path: [],
              field_name: response_key,
              conflicts: errored_nodes
            )

            return
          end

          if type1 != type2
            context.errors << GraphQL::StaticValidation::FieldsWillMergeError.new(
              "TODO diff types",
              nodes: [node1, node2],
              path: [],
              field_name: response_key,
              conflicts: ["TODO"]
            )
            return
          end

          if field1.name_and_arguments.arguments != field2.name_and_arguments.arguments
            # TODO: fix up args
            msg = "TODO: wrong args"
            context.errors << GraphQL::StaticValidation::FieldsWillMergeError.new(
              msg,
              nodes: [node1, node2],
              path: [],
              field_name: response_key,
              conflicts: ["wrong args"],
            )
            return
          end
        end

        def combine_abstract_and_concrete_parent_types(fields_with_abstract_parent_types, fields_with_concrete_parents)
          if fields_with_concrete_parents.empty?
            if fields_with_abstract_parent_types.empty?
              []
            else
              set = fields_with_abstract_parent_types.to_set.sort
              [cache[set]]
            end
          else
            if fields_with_abstract_parent_types.empty?
              fields_with_concrete_parents.values.map do |field|
                cache[field]
              end
            else
              fields_with_concrete_parents.values.map do |field|
                set = fields_with_abstract_parent_types.to_set.sort
                cache[set]
              end
            end
          end
        end

        def merge_child_selections
          @cache_merge_child_selections ||= cache[SelectionField.children(@fields)]
        end
      end

      class Cache
        def initialize(context)
          @cache = {}
          @context = context
          @hits = 0
          @misses = 0
        end

        def [](k)
          val = @cache[k]

          if val
            @hits += 1
            val
          else
            @misses += 1
            field_cache = FieldSetCache.new(k, cache: self, context: @context)
            @cache[k] = field_cache
            field_cache
          end
        end

        def to_s
          "#<Cache> size: #{@cache.keys.size} hits: #{@hits} misses: #{@misses}"
        end
      end

      def initialize(*)
        super
        @selection_builder = SelectionBuilder.new
        @cache = Cache.new(context)
      end

      def on_field(node, _parent)
        @selection_builder.enter_field(node, field_definition.type, parent_type_definition)

        if node.selections.any?
          @selection_builder.enter_generic_selection_container(node.selections)
        end

        super

        if node.selections.any?
          @selection_builder.leave_selection_container
        end
      end

      def on_inline_fragment(node, _parent)
        @selection_builder.enter_generic_selection_container(node.selections)
        super
        @selection_builder.leave_selection_container
      end

      def on_fragment_spread(node, _parent)
        @selection_builder.spread_fragment(node)
        super
      end

      def on_fragment_definition(node, _parent)
        @selection_builder.enter_fragment_definition(node)
        @selection_builder.enter_generic_selection_container(node.selections)
        super
        @selection_builder.leave_selection_container
      end

      def on_operation_definition(node, _parent)
        @selection_builder.enter_generic_selection_container(node.selections)
        super
        @selection_builder.leave_selection_container
      end

      def on_document(_node, _parent)
        super

        @selection_builder.roots.each do |root|
          root.compute_effective_selections
          @cache[root.field_set].fields_in_set_can_merge?
        end

        puts @cache
      end
    end
  end
end
