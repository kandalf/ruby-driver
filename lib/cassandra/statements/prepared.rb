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
    class Prepared
      include Statement

      # @return [String] original cql used to prepare this statement
      attr_reader :cql
      # @private
      attr_reader :result_metadata
      # @private
      attr_reader :params_types

      # @private
      def initialize(cql, params_metadata, result_metadata, trace_id, keyspace, statement, options, hosts, consistency, retries, client, futures_factory, schema)
        @cql             = cql
        @params_metadata = params_metadata
        @params_types    = params_metadata.map {|(_, _, _, type)| type}
        @result_metadata = result_metadata
        @trace_id        = trace_id
        @keyspace        = keyspace
        @statement       = statement
        @options         = options
        @hosts           = hosts
        @consistency     = consistency
        @retries         = retries
        @client          = client
        @schema          = schema
      end

      # Creates a statement bound with specific arguments
      #
      # @overload bind(*args)
      #   @deprecated Please pass a single {Hash} or {Array} of named or
      #     positional arguments accordingly, the `*args` style is deprecated.
      #
      #   @param args [*Object] positional arguments to bind, must contain the
      #     same number of parameters as the number of positional argument
      #     markers (`?`) in the CQL passed to {Cassandra::Session#prepare}.
      #
      # @overload bind(args)
      #   @param args [Hash, Array] named or positional arguments to bind, must
      #   contain the same number of parameters as the number of named
      #   (`:name`) or positional (`?`) markers in the original CQL passed to
      #   {Cassandra::Session#prepare}
      #
      # @return [Cassandra::Statements::Bound] bound statement
      def bind(*args)
        if args.size > 1 || (args.first && !(args.first.is_a?(::Array) || args.first.is_a?(::Hash)))
          ::Kernel.warn "[WARNING] Splat style (*params) positional arguments " \
                        "are deprecated, pass a Hash or an Array instead - " \
                        "called from #{caller.first}"
        else
          args = args.first
        end

        Util.assert_equal(@params_metadata.size, args.size) { "expecting exactly #{@params_metadata.size} bind parameters, #{args.size} given" }

        @params_metadata.each_with_index do |metadata, i|
          Util.assert_type(metadata[3], args[i]) { "argument for #{metadata[2].inspect} must be #{metadata[3].inspect}, #{args[i]} given" }
        end

        return Bound.new(@cql, @params_types, @result_metadata, args) if @params_metadata.empty?

        keyspace, table, _, _ = @params_metadata.first
        return Bound.new(@cql, @params_types, @result_metadata, args, keyspace) unless keyspace && table

        values = ::Hash.new
        @params_metadata.zip(args) do |(keyspace, table, column, type), value|
          values[column] = value
        end

        partition_key = @schema.create_partition_key(keyspace, table, values)

        Bound.new(@cql, @params_types, @result_metadata, args, keyspace, partition_key)
      end

      # @return [Cassandra::Execution::Info] execution info for PREPARE request
      def execution_info
        @info ||= Execution::Info.new(@keyspace, @statement, @options, @hosts, @consistency, @retries, @trace_id ? Execution::Trace.new(@trace_id, @client) : nil)
      end

      # @return [String] a CLI-friendly prepared statement representation
      def inspect
        "#<#{self.class.name}:0x#{self.object_id.to_s(16)} @cql=#{@cql.inspect}>"
      end
    end
  end
end
