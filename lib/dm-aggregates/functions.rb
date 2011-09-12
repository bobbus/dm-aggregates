module DataMapper
  module Aggregates
    module Functions
      include DataMapper::Assertions

      # Count results (given the conditions)
      #
      # @example the count of all friends
      #   Friend.count
      #
      # @example the count of all friends older then 18
      #   Friend.count(:age.gt => 18)
      #
      # @example the count of all your female friends
      #   Friend.count(:conditions => [ 'gender = ?', 'female' ])
      #
      # @example the count of all friends with an address (NULL values are not included)
      #   Friend.count(:address)
      #
      # @example the count of all friends with an address that are older then 18
      #   Friend.count(:address, :age.gt => 18)
      #
      # @example the count of all your female friends with an address
      #   Friend.count(:address, :conditions => [ 'gender = ?', 'female' ])
      #
      # @param property [Symbol] of the property you with to count (optional)
      # @param  opts [Hash, Symbol] the conditions
      #
      # @return [Integer] return the count given the conditions
      #
      # @api public
      def count(*args)
        query         = args.last.kind_of?(Hash) ? args.pop : {}
        property_name = args.first

        if property_name
          assert_kind_of 'property', property_by_name(property_name), Property
        end

        aggregate(query.merge(:fields => [ property_name ? property_name.count : :all.count ])).to_i
      end

      # Get the lowest value of a property
      #
      # @example the age of the youngest friend
      #   Friend.min(:age)
      #
      # @example  the age of the youngest female friend
      #   Friend.min(:age, :conditions => [ 'gender = ?', 'female' ])
      #
      # @param property [Symbol] the property you wish to get the lowest value of
      # @param  opts [Hash, Symbol] the conditions
      #
      # @return [Integer] return the lowest value of a property given the conditions
      #
      # @api public
      def min(*args)
        query         = args.last.kind_of?(Hash) ? args.pop : {}
        property_name = args.first

        assert_property_type property_name, ::Integer, ::Float, ::BigDecimal, ::DateTime, ::Date, ::Time

        aggregate(query.merge(:fields => [ property_name.min ]))
      end

      # Get the highest value of a property
      #
      # @example the age of the oldest friend
      #   Friend.max(:age)
      #
      # @example the age of the oldest female friend
      #   Friend.max(:age, :conditions => [ 'gender = ?', 'female' ])
      #
      # @param property [Symbol] the property you wish to get the highest value of
      # @param  opts [Hash, Symbol] the conditions
      #
      # @return [Integer] return the highest value of a property given the conditions
      #
      # @api public
      def max(*args)
        query         = args.last.kind_of?(Hash) ? args.pop : {}
        property_name = args.first

        assert_property_type property_name, ::Integer, ::Float, ::BigDecimal, ::DateTime, ::Date, ::Time

        aggregate(query.merge(:fields => [ property_name.max ]))
      end

      # Get the average value of a property
      #
      # @example the average age of all friends
      #   Friend.avg(:age)
      #
      # @example the average age of all female friends
      #   Friend.avg(:age, :conditions => [ 'gender = ?', 'female' ])
      #
      # @param property [Symbol] the property you wish to get the average value of
      # @param  opts [Hash, Symbol] the conditions
      #
      # @return [Integer] return the average value of a property given the conditions
      #
      # @api public
      def avg(*args)
        query         = args.last.kind_of?(Hash) ? args.pop : {}
        property_name = args.first

        assert_property_type property_name, ::Integer, ::Float, ::BigDecimal

        aggregate(query.merge(:fields => [ property_name.avg ]))
      end

      # Get the total value of a property
      #
      # @example the total age of all friends
      #   Friend.sum(:age)
      #
      # @example the total age of all female friends
      #   Friend.max(:age, :conditions => [ 'gender = ?', 'female' ])
      #
      # @param property [Symbol] the property you wish to get the total value of
      # @param  opts [Hash, Symbol] the conditions
      #
      # @return [Integer] return the total value of a property given the conditions
      #
      # @api public
      def sum(*args)
        query         = args.last.kind_of?(::Hash) ? args.pop : {}
        property_name = args.first

        assert_property_type property_name, ::Integer, ::Float, ::BigDecimal

        aggregate(query.merge(:fields => [ property_name.sum ]))
      end

      # Perform aggregate queries
      #
      # @example the count of friends
      #   Friend.aggregate(:all.count)
      #
      # @example the minimum age, the maximum age and the total age of friends
      #   Friend.aggregate(:age.min, :age.max, :age.sum)
      #
      # @example the average age, grouped by gender
      #   Friend.aggregate(:age.avg, :fields => [ :gender ])
      #
      # @param aggregates [Symbol, ...] operators to aggregate with
      # @param query [Hash] the conditions
      #
      # @return [Array,Numeric,DateTime,Date,Time] the results of the
      #   aggregate query
      #
      # @api public
      def aggregate(*args)
        query = args.last.kind_of?(Hash) ? args.pop : {}

        query[:fields] ||= []
        query[:fields]  |= args
        query[:fields].map! { |f| normalize_field(f) }

        raise ArgumentError, 'query[:fields] must not be empty' if query[:fields].empty?

        unless query.key?(:order)
          # the current collection/model is already sorted by attributes
          # and since we are projecting away some of the attributes,
          # and then performing aggregate functions on the remainder,
          # we need to honor the existing order, as if it were already
          # materialized, and we are looping over the rows in order.

          directions = direction_map

          query[:order] = []

          # use the current query order for each property if available
          query[:fields].each do |property|
            next unless property.kind_of?(Property)
            query[:order] << directions.fetch(property, property)
          end
        end

        query = scoped_query(query)

        if query.fields.any? { |p| p.kind_of?(Property) }
          query.repository.aggregate(query.update(:unique => true))
        else
          query.repository.aggregate(query).first  # only return one row
        end
      end

      private

      def assert_property_type(name, *types)
        if name.nil?
          raise ArgumentError, 'property name must not be nil'
        end

        property = property_by_name(name)
        type     = property.dump_class

        unless types.include?(type)
          raise ArgumentError, "#{name} must be #{types * ' or '}, but was #{type}"
        end
      end

      def normalize_field(field)
        assert_kind_of 'field', field, DataMapper::Query::Operator, Symbol, Property

        case field
          when DataMapper::Query::Operator
            if field.target == :all
              field
            else
              field.class.new(property_by_name(field.target), field.operator)
            end

          when Symbol
            property_by_name(field)

          when Property
            field
        end
      end

      def direction_map
        direction_map = {}
        self.query.order.each do |direction|
          direction_map[direction.target] = direction
        end
        direction_map
      end
    end
  end
end
