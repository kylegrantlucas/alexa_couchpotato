require 'json'
require 'alexa_objects'
require 'httparty'
require 'numbers_in_words'
require 'numbers_in_words/duck_punch'
require 'active_support'
require 'active_support/core_ext'
require 'chronic'
require 'alexa_couchpotato/version'
require 'sinatra/base'

module Sinatra
  module Couchpotato
    def self.registered(app)
      app.post '/alexa_cp' do
        content_type :json
        search_endpoint = "http://#{settings.config.couchpotato.url}/movies/api/#{settings.config.couchpotato.api_key}/search" 
        add_endpoint = "http://#{settings.config.couchpotato.url}/movies/api/#{settings.config.couchpotato.api_key}/movie.add"

        #halt 400, "" unless settings.config.application_id && @application_id == settings.config.application_id

        if @echo_request.launch_request?
          response = AlexaObjects::Response.new
          response.spoken_response = "I'm ready to download you movies."
          response.end_session = false
          response.without_card.to_json
          puts @echo_request.slots
        elsif @echo_request.intent_name == "ControlCouchpotato"
          count = 1
          begin
            case count
            when 1
              title = @echo_request.slots["movie"]
            when 2
              word_arr =  @echo_request.slots["movie"].split(' ')
              nums = word_arr.map {|x|x.in_numbers}
              title = ""
              word_arr.each_with_index do |x, index|
                title << (nums[index] != 0 ? "#{nums[index]}" : x)
                title << " " unless index == word_arr.length-1
              end
            end
            query = HTTParty.get(URI.escape("#{search_endpoint}?q=#{title}"))
            if query["movies"] && query["movies"].count == 1
              movie = query["movies"].first
            elsif query["movies"] && query["movies"].count > 1
              movie = query["movies"]
            end
            movie = false if count == 5 && movie.nil?
            count += 1      
          end until movie != nil
          response = AlexaObjects::Response.new

          if [movie].flatten(1).count == 1 && movie != false
            add_query = HTTParty.get(URI.escape("#{add_endpoint}?title=#{movie["titles"].first}&identifier#{movie["imdb"]}"))
            if add_query["success"] = true
              response.end_session = true
              response.spoken_response = "okay, downloading #{movie["titles"].first}"
            elsif movie && add_query["success"] = false
              response.end_session = true
              response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because it wouldn't add to the server"
            end
          elsif movie != false && [movie].flatten(1).count > 1
            @@movies = movie
            response.end_session = false
            response.reprompt_text = "Which movie would you like me to download? #{movie.map {|m| m["titles"].first }.to_sentence(:last_word_connector => ' or ')}"
          elsif movie == false
            response.end_session = true
            response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
          else
            response.end_session = true
            response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
          end

          response.without_card.to_json
        elsif @echo_request.intent_name == "RespondCouchpotato"
          ordinal = Chronic::Numerizer.numerize(@echo_request.slots["listvalue"]).split(' ').last
          number = ordinal[0]
          movie = @@movies[number.to_i+1]
          query = HTTParty.get(URI.escape("#{add_endpoint}?title=#{movie["titles"].first}&identifier#{movie["imdb"]}"))
          response = AlexaObjects::Response.new
          if movie != false && query["success"] = true
            response.end_session = true
            response.spoken_response = "okay, downloading #{movie["titles"].first}"
          elsif movie == false
            response.end_session = true
            response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
          elsif movie && query["success"] = false
            response.end_session = true
            response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because it wouldn't add to the server"
          end
          response.without_card.to_json
        elsif @echo_request.intent_name == "EndSession"
          puts @echo_request.slots
          response = AlexaObjects::Response.new
          response.end_session = true
          response.spoken_response = "exiting couchpoato"
          response.without_card.to_json
        elsif @echo_request.session_ended_request?
          response = AlexaObjects::Response.new
          response.end_session = true
          response.without_card.to_json
        end
      end
    end
  end

  register Couchpotato
end