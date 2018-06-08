require 'json'
require 'twitter'

class Collector
  ACCOUNTS = [
    'NJTRANSIT_RVL',
    'NJTRANSIT_PVL',
    'NJTRANSIT_MBPJ',
    'NJTRANSIT_MOBO',
    'NJTRANSIT_ACRL',
    'NJTRANSIT_ME',
    'NJTRANSIT_NJCL',
    'NJTRANSIT_NEC',
  ]

  def initialize
    if File.exist?("#{Dir.pwd}/data.json")
      @data = JSON.parse(File.read("#{Dir.pwd}/data.json"))
    end

    config = {
      consumer_key:    ENV['TWITTER_KEY'],
      consumer_secret: ENV['TWITTER_SECRET'],
    }

    @client = Twitter::REST::Client.new(config)
    @data = {}
  end

  def collect
    def collect_with_max_id(collection=[], max_id=nil, &block)
      response = yield(max_id)
      collection += response
      response.empty? ? collection.flatten : collect_with_max_id(collection, response.last.id - 1, &block)
    end

    def @client.get_all_tweets(user)
      collect_with_max_id do |max_id|
        options = {count: 200, include_rts: true}
        options[:max_id] = max_id unless max_id.nil?
        user_timeline(user, options)
      end
    end

    ACCOUNTS.each do |account|
      tweets = @client.get_all_tweets(account)
      #tweets = @client.user_timeline(account, { count: 800 })
      tweets.each do |tweet|
        text = tweet.text
        next unless text.downcase.include?('cancel')

        # Quick and easy regex. Should match on the following string:
        # "NJCL train #3511, the 5:03pm from"
        if text.match?(/#\d+/)
          train_id = text.match(/#\d+/)[0]
        # More annoying match. Should match on the following string:
        # "PVL train 1652 the 10:24am from"
        elsif text.match?(/train \d*/)
          begin
            train_id = '#' + text.match(/train \d*/)[0].split('train ')[1]
          rescue Exception
            puts "DID NOT MATCH: '#{text}'"
          end
        else
          puts "DID NOT MATCH: '#{text}'"
        end

        # Skip if already seen this tweet before
        if (!@data["#{account}-#{train_id}"].nil?)
          next if @data["#{account}-#{train_id}"].include?(tweet.created_at)
        end

        # Initialize new train's data location
        if (@data["#{account}-#{train_id}"].nil?)
          @data["#{account}-#{train_id}"] = []
        end

        @data["#{account}-#{train_id}"] << tweet.created_at
      end
    end

    sort_data(@data)
  end

  private

  def sort_data(data)
    # First, sort by number of cancellations per train.
    trains = data.sort_by { |(_, train_delays)| train_delays.length }

    # The above method turns the Hash into an Array, and sorts in ascending order.
    # Turn back into a Hash, and put in descending order.
    Hash[trains.reverse]
  end
end

data = Collector.new.collect

File.open("#{Dir.pwd}/data.json", 'w') do |f|
  f.write data.to_json
end

data.each do |train_id, train_delays|
  _, line_and_id = train_id.split('_')
  line, id = line_and_id.split('-')
  puts "#{line} #{id}: #{train_delays.length}"
end
