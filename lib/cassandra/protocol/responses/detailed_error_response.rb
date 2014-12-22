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
  module Protocol
    class DetailedErrorResponse < ErrorResponse
      attr_reader :details

      def initialize(code, message, details)
        super(code, message)
        @details = details
      end

      def to_error(statement = nil)
        case code
        when 0x1000 then Errors::UnavailableError.new(@message, statement, @details[:cl], @details[:required], @details[:alive])
        when 0x1100 then Errors::WriteTimeoutError.new(@message, statement, @details[:write_type], @details[:cl], @details[:blockfor], @details[:received])
        when 0x1200 then Errors::ReadTimeoutError.new(@message, statement, @details[:data_present], @details[:cl], @details[:blockfor], @details[:received])
        when 0x2400 then Errors::AlreadyExistsError.new(@message, statement, @details[:ks], @details[:table])
        when 0x2500 then Errors::UnpreparedError.new(@message, statement, @details[:id])
        else
          super
        end
      end

      def to_s
        "#{super} #{@details}"
      end
    end
  end
end
