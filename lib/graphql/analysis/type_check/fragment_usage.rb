module GraphQL
  module Analysis
    class TypeCheck
      class FragmentUsage
        attr_reader :name, :usages, :definitions
        def initialize(name)
          @name = name
          @usages = []
          @definitions = []
        end

        def used_for(on_type:, node:, depth:, root_node:)
          @usages << Occurrence.new(
            type: on_type,
            node: node,
            depth: depth,
            root_node: root_node,
          )
        end

        def unused?
          @usages.none?
        end

        def undefined?
          @definitions.none?
        end

        def duplicated?
          @definitions.length > 1
        end

        def defined(node:, as_type:)
          @definitions << Occurrence.new(
            node: node,
            type: as_type,
            depth: 0,
            root_node: node,
          )
        end

        class Occurrence
          attr_reader :type, :node, :depth, :root_node
          def initialize(type:, node:, depth:, root_node:)
            @type = type
            @node = node
            @depth = depth
            @root_node = root_node
          end
        end

        class << self
          # @param fragment_usages [Hash<String, FragmentUsage]
          def build_errors(fragment_usages, schema)
            errors = []
            fragment_usages.values.each do |fragment_usage|
              if fragment_usage.unused?
                errors << build_analysis_error("Unused fragment definition: #{fragment_usage.name}", fragment_usage.definitions.first)
              elsif fragment_usage.undefined?
                # TODO: would be nice to include _all_ usages
                errors << build_analysis_error("Undefined fragment spread: ...#{fragment_usage.name}", fragment_usage.usages.first.node)
              elsif fragment_usage.duplicated?
                errors << build_analysis_error("Duplicate fragment name: #{fragment_usage.name}", fragment_usage.definitions.first)
              else
                defn = fragment_usage.definitions.first
                defn_type = defn.type
                fragment_usage.usages.each do |usage|
                  # Maybe nil if the type was undefined
                  if usage.type && defn_type && !TypeCondition.possible_type_condition?(usage.type, defn_type, schema)
                    errors << build_analysis_error("Impossible fragment spread: ...#{fragment_usage.name} can't apply to #{usage.type}", usage.node)
                  elsif usage.root_node == defn.node
                    errors << build_analysis_error("Circular fragment: #{fragment_usage.name} spreads itself", usage.root_node)
                  end
                end
              end
            end
            errors
          end

          private

          def build_analysis_error(msg, node)
            err = GraphQL::AnalysisError.new(msg)
            err.ast_node = node
            err
          end

          # @example Cicular references
          #   { ... A ... D }
          #   frag A { ... B }
          #   frag B { ... C }
          #   frag C { ... A }
          #   frag D { ... A }
          def find_circles(frag_name, frag_usages)
            frag_usage = frag_usages[frag_name]
            roots = frag_usage.usages.map(&:root_node)
            next_usages = frag_usages.select { |k, v| (v.definitions & roots).any? }.values
          end

          # ????
          def has_nested_spread(name, frag_usage, frag_usages)
            roots = frag_usage.usages.map(&:root_node).select { |node| node.is_a?(GraphQL::Language::Nodes::FragmentDefiniton) }
            next_usages = roots.map { |node| frag_usages[node.name] }
            next_usages.map { |usage| has_nested_spread(name, usage, frag_usages)}
          end
        end
      end
    end
  end
end
