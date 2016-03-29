require 'twitter'
require 'genius'
require 'marky_markov'

puts 'Loading secrets.'
HOUR = 60 * 60
secrets = YAML.load_file('secrets.yaml')
artists = YAML.load_file('artists.yaml')
g_artists = []
parse_artists = false
debug_mode = false
build_dictionary = false
print_example_strings = false

unless debug_mode
  puts 'Configuring twitter client.'
  @twitter_client = Twitter::REST::Client.new do |conf|
    conf.consumer_key     = secrets['twitter_consumer_key']
    conf.consumer_secret  = secrets['twitter_consumer_secret']
    conf.access_token     = secrets['twitter_access_token'] if secrets.key?('twitter_access_token')
    conf.access_token_secret = secrets['twitter_access_token_secret'] if secrets.key?('twitter_access_token_secret')
  end
end

puts 'Configuring Genius'
Genius.access_token = secrets['genius_access_token']
Genius.text_format = 'plain'

# If we're parsing artists, we load all artists from artists.yaml, try to find an artist ID for them, and then save them in ids.yaml
if parse_artists
  puts 'Parsing Artists'
  artists.each do |artist, song|
    if song
      search_term = "#{artist} #{song}"
    else
      search_term = artist
    end
    song = Genius::Song.search(search_term).first
    #puts "Song for #{artist} is #{song.title}"
    g_artist = song.primary_artist
    puts "Chosen artist for #{artist} is #{g_artist.name} "
    g_artists.push g_artist
  end

  # Dump artist and ids into database

  puts "Dumping #{g_artists.length} artists/ids to file."
  artist_ids = {}
  g_artists.each do |g_artist|
    artist_ids[g_artist.id] = g_artist.name
  end
  File.open("ids.yaml", 'w') do |file|
    file.write(YAML.dump(artist_ids))
  end
end



# Markov stuff
require 'marky_markov'
markov = MarkyMarkov::Dictionary.new('lyrics')

# If we're building a dictionary, we need to add referents from 20 most popular songs of each artist
if build_dictionary
  # If we aren't parsing artists, we need to load the ids and build a list of g_artists
  if !parse_artists
    puts 'Building list of artist objects from ids'
    artist_ids = YAML.load_file('ids.yaml')
    artist_ids.each do |id, name|
      g_artists.push Genius::Artist.find(id)
    end
  end

  puts 'Building dictionary.'
  dic_strings = []

  g_artists.each do |artist|
    songs = artist.songs(params:{sort: 'popularity'})
    songs.each do |song|
      refs = Genius::Referent.where({song_id: song.id})
      puts "Got #{refs.length} refs for #{song.title} by #{artist.name}"
      # Put the fragment of each referent into the list of dic strings
      refs.each do |ref|
        dic_strings.push ref.fragment
      end
    end
  end

  dic_strings.each do |string|
    markov.parse_string string
  end
  markov.save_dictionary!
end

if print_example_strings
  puts "Type 1"
  5.times do
    puts markov.generate_n_words rand(3..30)
  end
  puts "Type 2"
  5.times do
    puts markov.generate_n_sentences rand(1..4)
  end


end

running = true
while running
  if rand(1..2) == 1 #type 1
    tweet_text = markov.generate_n_words rand(3..30)
    while tweet_text.length > 140
      tweet_text = markov.generate_n_words rand(3..30)
    end
  else # type 2
    tweet_text = markov.generate_n_sentences rand(1..4)
    while tweet_text.length > 140
      tweet_text = markov.generate_n_sentences rand(1..4)
    end
  end

  puts "Tweeting: #{tweet_text}"
  @twitter_client.update(tweet_text) unless debug_mode
  sleeptime = (rand(1..4) * HOUR)
  puts "Sleeping for #{sleeptime / HOUR} hours"
  sleep sleeptime
end