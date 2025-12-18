# frozen_string_literal: true

class Venue
  attr_reader :id, :name

  def initialize(id, name)
    @id = id
    @name = name
  end

  def self.from_broadcast(payload)
    id = payload['venue']['objectId']
    name = payload['venue']['name']

    Venue.new(id, name)
  end

  def to_json(_options = {})
    @name
  end
end

class Event
  attr_reader :id, :description, :tags, :start_time, :end_time, :venue, :ticket_url, :updated_at
  attr_accessor :name, :updated

  def initialize(id, name, description, tags, start_time, end_time, venue, ticket_url, updated_at)
    @id = id
    @name = name
    @description = description
    @tags = tags
    @start_time = DateTime.parse(start_time)
    @end_time = DateTime.parse(end_time || event_start + Rational(4, 24)) # Default duration 4 hours
    @venue = venue
    @ticket_url = ticket_url
    @updated_at = updated_at
    @updated = false
  end

  def self.from_broadcast(payload)
    id = payload['objectId']
    name = payload['name']
    description = payload['details']
    tags = payload['tags']
    start_time = payload['start_time']
    end_time = payload['custom_fields']['end_time']
    venue = Venue.from_broadcast(payload)
    ticket_url = payload['custom_fields']['ticketUrl']
    updated_at = payload['updatedAt']

    Event.new(id, name, description, tags, start_time, end_time, venue, ticket_url, updated_at)
  end

  def self.from_events_edge(payload)
    id = payload['id']
    name = payload['name']
    description = payload['details']
    tags = payload['tags']
    start_time = payload['start_time']
    end_time = payload['custom_fields']['end_time']
    venue = Venue.new(-1, payload['place']['name'])
    ticket_url = payload['custom_fields']['ticketUrl']
    updated_at = payload['updatedAt']

    Event.new(id, name, description, tags, start_time, end_time, venue, ticket_url, updated_at)
  end

  def has_changed(old_event)
    return false if DateTime.parse(old_event['updated_at']) == DateTime.parse(@updated_at)

    @name != old_event['name'] ||
      @tags.sort != old_event['tags'].sort ||
      @start_time != DateTime.parse(old_event['start_time']) ||
      @end_time != DateTime.parse(old_event['end_time']) ||
      @venue.name != old_event['venue']['name']
  end

  def to_json(_options = {})
    {
      id: @id,
      name: @name,
      tags: @tags,
      start_time: @start_time,
      end_time: @end_time,
      venue: @venue.to_json,
      updated_at: @updated_at
    }.to_json
  end
end
