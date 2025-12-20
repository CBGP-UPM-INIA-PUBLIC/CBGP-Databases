module CBGP
  class Dumpers
    def self.citation(doi:)
      return '' unless doi

      begin
        ref = RestClient.get("https://citation.doi.org/format?doi=#{doi}&style=apa&lang=en-US")
      rescue StandardError => e
        warn e.inspect
        return ''
      end
      ref
    end
  end
end
