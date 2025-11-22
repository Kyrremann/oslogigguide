require 'json'
require 'httparty'

urls = [
  {
    'url': 'https://www.goldie.no/api/eventsEdge',
    'type': ''
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=mTP5efb3tQ&recommended=false&hostname=www-brewgata-no.filesusr.com&city=Oslo',
    'type': 'broadcast'
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=EBIs19AJFr&recommended=false&hostname=www-revolveroslo-no.filesusr.com&city=Oslo',
    'type': 'broadcast'
  },
  {
    'url': 'https://demo.broadcastapp.no/api/layoutWidgetCors?limit=99&venue=none&recommended=false&hostname=www.vaterlandoslo.no&city=Oslo&key=zXg-2T9s4NWH_NLD6R5KjsDgtT3aeWL2',
    'type': 'broadcast'
  }
]

class Venue
  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.from_broadcast(payload)
    id = payload['venue']['objectid']
    name = payload['venue']['name']

    Venue.new(id, name)
  end

  def to_json(_options = {})
    @name
  end
end

class Event
  attr_reader :start_time

  def initialize(id, name, tags, start_time, venue)
    @id = id
    @name = name
    @tags = tags
    @start_time = start_time
    @venue = venue
  end

  def self.from_broadcast(payload)
    id = payload['objectid']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    venue = Venue.from_broadcast(payload)

    Event.new(id, name, tags, start_time, venue)
  end

  def self.from_goldie(payload)
    id = payload['id']
    name = payload['name']
    tags = payload['tags']
    start_time = payload['start_time']
    venue = Venue.new(-1, 'Goldie')

    Event.new(id, name, tags, start_time, venue)
  end

  def to_json(_options = {})
    {
      name: @name,
      tags: @tags,
      start_time: @start_time,
      venue: @venue.to_json
    }.to_json
  end
end

events = []

urls.each do |source|
  response = HTTParty.get(source[:url])
  payload = JSON.parse(response.body)
  if source[:type] == 'broadcast'
    payload['results'].each do |event|
      events << Event.from_broadcast(event)
    end
  else
    payload.each do |event|
      events << Event.from_goldie(event)
    end
  end
end

events.sort_by!(&:start_time)

puts events.to_json
