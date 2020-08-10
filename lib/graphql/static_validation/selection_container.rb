# frozen_string_literal: true
module GraphQL
  module StaticValidation
    class SelectionContainer
      attr_reader :selection_set, :direct_fields, :direct_spreads, :done, :in_progress, :effective_selections

      class << self
        def children(fields)
          child_selections = fields.each_with_object(Set.new) do |selection_field, set|
            set.merge(selection_field.selection_container.effective_selections)
          end

          field_set(child_selections)
        end

        def field_set(effective_selections)
          Set.new(effective_selections.flat_map(&:direct_fields)).sort
        end
      end

      def initialize(selection_set)
        @selection_set = selection_set
        @in_progress = false
        @done = false
        @direct_spreads = []
        @direct_fields = []
        @effective_selections = Set.new([self])
      end

      def add_spread(selection_container)
        @direct_spreads << selection_container
      end

      def add_field(selection_field)
        @direct_fields << selection_field
      end

      def field_set
        self.class.field_set(@effective_selections)
      end

      def compute_effective_selections
        return if @in_progress || @done

        @in_progress = true

        direct_fields.each do |field|
          field.selection_container.compute_effective_selections
        end

        direct_spreads.each do |spread|
          next if spread.in_progress

          if spread.done
            if !@effective_selections.include?(spread)
              @effective_selections.merge(spread.effective_selections)
            end
          else
            spread.compute_effective_selections
            @effective_selections.merge(spread.effective_selections)
          end
        end

        @in_progress = false
        @done = true
      end
    end
  end
end
