class Hiera
  module Backend
    class Profyles_backend
      def initialize(cache=nil)
        begin
          require 'yaml'
        rescue LoadError
          require 'rubygems'
          require 'yaml'
        end
        Hiera.debug("Hiera Profyles backend starting")
        @cache = cache || Filecache.new
      end

      ## use Backend.datasources to retrieve the existing hierarchy, then catch the places that it inserts the array string ('mongo,mysql,postgres'),
      ## and do our own interpolation. then, once we have that array, we pass it back to the lookup using the new array as an 'override'
      #####################
      def lookup(key, scope, order_override, resolution_type)
        hierarchy = parse_hierarchy(scope)
        answer = nil

        Hiera.debug("Looking up #{key} in Profyles backend")

        Backend.datasourcefiles(:profyles, scope, "yaml", order_override, hierarchy) do |source, yamlfile|
          data = @cache.read_file(yamlfile, Hash) do |data|
            YAML.load(data) || {}
          end

          next if data.empty?
          next unless data.include?(key)

          # Extra logging that we found the key. This can be outputted
          # multiple times if the resolution type is array or hash but that
          # should be expected as the logging will then tell the user ALL the
          # places where the key is found.
          Hiera.debug("Found #{key} in #{source}")

          # for array resolution we just append to the array whatever
          # we find, we then goes onto the next file and keep adding to
          # the array
          #
          # for priority searches we break after the first found data item
          new_answer = Backend.parse_answer(data[key], scope)
          case resolution_type
          when :array
            raise Exception, "Hiera type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of? Array or new_answer.kind_of? String
            answer ||= []
            answer << new_answer
          when :hash
            raise Exception, "Hiera type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
            answer ||= {}
            answer = Backend.merge_answer(new_answer,answer)
          else
            answer = new_answer
            break
          end
        end

        return answer
      end

      private

      def file_exists?(path)
        File.exist? path
      end

      def parse_hierarchy(scope)
        hierarchy = nil

        # Get the existing hierarchy that would be searched
        # iterate through each line
        Backend.datasources(scope) do |source|
          hierarchy ||= []

          # parse if there is a comma seperated anything
          if source =~ /.+\,.+/
            # interpolate the array sections into and expanded map, then flatten to an array
            hierarchy << source.split("/").inject() {|paths, components|
              paths = [*paths]
              components = components.split(",")
              components = [""] if components.empty?
              paths.map {|path|
                components.map {|component|
                  "#{path}/#{component}"
                }
              }.flatten
            }
          else
            # otherwise just append
            hierarchy << source
          end
        end

        return hierarchy
      end
    end
  end
end