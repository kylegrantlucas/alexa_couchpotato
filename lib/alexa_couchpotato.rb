require 'json'
require 'alexa_objects'
require 'curb'
require 'oj'
require 'numbers_in_words'
require 'numbers_in_words/duck_punch'
require 'active_support'
require 'active_support/core_ext'
require 'chronic'
require 'alexa_couchpotato/version'
require 'sinatra/extension'

module Couchpotato
  extend Sinatra::Extension

  helpers do
    def control_couchpotato
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
        
        query = Oj.load(Curl.get(URI.escape("#{search_endpoint}?q=#{title}").body_str)) rescue nil
        
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
          response.spoken_response = "okay, downloading #{movie["titles"].first}"
        elsif movie && add_query["success"] = false
          response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because it wouldn't add to the server"
        end
      elsif movie != false && [movie].flatten(1).count > 1
        @@movies = movie
        response.end_session = false
        response.reprompt_text = "Which movie would you like me to download? #{movie.map {|m| m["titles"].first }.to_sentence(:last_word_connector => ' or ')}"
      elsif movie == false
        response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
      else
        response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
      end

      response.to_json
    end

    def respond_couchpotato
      ordinal = Chronic::Numerizer.numerize(@echo_request.slots["listvalue"]).split(' ').last
      number = ordinal[0]
      movie = @@movies[number.to_i+1]
      query = HTTParty.get(URI.escape("#{add_endpoint}?title=#{movie["titles"].first}&identifier#{movie["imdb"]}"))
      response = AlexaObjects::Response.new
      if movie != false && query["success"] = true
        response.spoken_response = "okay, downloading #{movie["titles"].first}"
      elsif movie == false
        response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because the search came up empty"
      elsif movie && query["success"] = false
        response.spoken_response = "sorry, I wasn't able to find #{@echo_request.slots["movie"]} because it wouldn't add to the server"
      end
      response.to_json
    end

    def add_endpoint
      "http://#{settings.config.couchpotato.url}/movies/api/#{settings.config.couchpotato.api_key}/movie.add"
    end

    def search_endpoint
      "http://#{settings.config.couchpotato.url}/movies/api/#{settings.config.couchpotato.api_key}/search" 
    end
  end
end
