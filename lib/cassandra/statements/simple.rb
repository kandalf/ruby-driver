# encoding: utf-8

#--
# Copyright 2013-2014 DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

module Cassandra
  module Statements
    class Simple
      include Statement

      # @return [String] original cql used to prepare this statement
      attr_reader :cql
      # @return [Array<Object>] a list of positional parameters for the cql
      attr_reader :params

      # @private
      attr_reader :params_types

      # @overload initialize(cql, *params)
      #   @deprecated Please pass a single {Hash} or {Array} of named or
      #     positional arguments accordingly, the `*params` style is deprecated.
      #
      #   @param cql [String] a cql statement
      #   @param params [*Object] positional arguments for the query
      #
      # @overload initialize(cql, params)
      #   @param cql [String] a cql statement
      #   @param params [Hash, Array] named or positional arguments for the
      #     query
      #
      # @raise [ArgumentError] if cql statement given is not a String
      def initialize(cql, *params)
        unless cql.is_a?(::String)
          raise ::ArgumentError, "cql must be a string, #{cql.inspect} given"
        end

        if params.size > 1 || (params.first && !(params.first.is_a?(::Array) || params.first.is_a?(::Hash)))
          ::Kernel.warn "[WARNING] Splat style (*params) positional arguments " \
                        "are deprecated, pass a Hash or an Array instead - " \
                        "called from #{caller.first}"
          @params       = params
          @params_types = params.map(&method(:guess_type))
        else
          params = params.first || EMPTY_LIST

          case params
          when ::Hash
            @params_types = params.map {|_, value| guess_type(value)}
          when ::Array
            @params_types = params.map {|value| guess_type(value)}
          else
            raise ::ArgumentError, "params must be a Hash or an Array, #{params.inspect} given"
          end

          @params = params
        end

        @cql = cql
      end

      # @return [String] a CLI-friendly simple statement representation
      def inspect
        "#<#{self.class.name}:0x#{self.object_id.to_s(16)} @cql=#{@cql.inspect} @params=#{@params.inspect}>"
      end

      # @param other [Object, Cassandra::Statements::Simple] object to compare
      # @return [Boolean] whether the statements are equal
      def eql?(other)
        other.is_a?(Simple) &&
          @cql == other.cql &&
          @params == other.params
      end

      alias :== :eql?

      private
      TYPE_GUESSES = {
        String => :varchar,
        Fixnum => :bigint,
        Float => :double,
        Bignum => :varint,
        BigDecimal => :decimal,
        TrueClass => :boolean,
        FalseClass => :boolean,
        NilClass => :bigint,
        Uuid => :uuid,
        TimeUuid => :uuid,
        IPAddr => :inet,
        Time => :timestamp,
        Hash => :map,
        Array => :list,
        Set => :set,
      }.freeze

      def guess_type(value)
        type = TYPE_GUESSES[value.class]

        raise ::ArgumentError, "Unable to guess the type of the argument: #{value.inspect}" unless type

        if type == :map
          pair = value.first
          [type, guess_type(pair[0]), guess_type(pair[1])]
        elsif type == :list
          [type, guess_type(value.first)]
        elsif type == :set
          [type, guess_type(value.first)]
        else
          type
        end
      end
    end
  end
end
