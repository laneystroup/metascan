module Metascan

  require 'typhoeus'
  require 'json'

  # Paths to use for api calls.
  PATHS = {
    :scan_file            => "https://api.metascan-online.com/v1/file",
    :results_by_data_id   => "https://api.metascan-online.com/v1/file/",
    :results_by_file_hash => "https://api.metascan-online.com/v1/hash/"
  }

  # A single scan on the Metascan service.
  # Initialized with the parameters to scan,
  # exposes methods to inspect the scan results.
  class Scan
    attr_reader :data_id
    attr_reader :filename

    def initialize(filename, client, archivepwd: nil)
      @filename   = filename
      @client     = client
      @archivepwd = archivepwd
    end

    # Initiate a scan of @filename
    def run
      self.request.run
    end

    # Construct and return the request I use, for the purpose of
    # queueing in a Typhoeus::Hydra.
    def request
      request = Typhoeus::Request.new(
        Metascan::PATHS[:scan_file],
        headers: {
          'filename' => @filename,
          'archivepwd' => @archivepwd,
          'apikey' => @client.api_key
        }.select { |k, v| !v.nil? },
        method: :post,
        body: { file: File.open(@filename, "r") }
      )

      request.on_complete do |r|
        @data_id = JSON.parse(r.body)["data_id"]
      end

      request
    end

    # Returns true iff the Metascan virus scan found no threats.
    # If POLL is true (false by default) then retrieve_results first.
    def clean?(poll: false)
      self.results(poll: poll)["scan_results"]["scan_all_result_i"] == 0
    end

    # Only useful for testing.
    def results=(results)
      @results = results
    end

    # Return the results of my scan.
    # If the optional argument "poll" is set to true, then attempt
    # to requery Metascan for the results before returning them.
    def results(poll: false)
      if poll and
        (!@results or @results["scan_results"]["progress_percentage"] < 100) then
        retrieve_results.run
      end
      @results
    end

    # Returns a HTTP request to retrieve the latest scan results for me.
    # Fails if called before @data_id is set (when self.run is called, or
    # my Batch runs me)
    def retrieve_results
      request = Typhoeus::Request.new(
        Metascan::PATHS[:results_by_data_id] + @data_id,
        headers: {
          'apikey' => @client.api_key
        },
        method: :get
      )

      request.on_complete do |r|
        @results = JSON.parse(r.body)
      end

      request
    end
  end
end
