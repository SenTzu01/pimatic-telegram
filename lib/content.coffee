module.exports = (env) ->
  
  commons = require('pimatic-plugin-commons')(env)
  fs = require('fs')
  Promise = env.require 'bluebird'
  
  class Content
    
    constructor: (input, @TelegramPlugin) ->
      
      if typeof input is "string" or typeof input is "number"
        input = ['"' + input + '"']
      @input = input
      @base = commons.base @, "Content"
   
    set: (@input) ->
    
    get: () =>
      @TelegramPlugin.evaluateStringExpression(@input).then( (content) =>
        return Promise.resolve content
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, __("Could not parse \"%s\"", @input)
      )
      
  class TextContent extends Content
    constructor: (input...) ->
      super(input...)
      @base = commons.base @, "TextContent"
      
    get: () ->
      super()
      
  class MediaContent extends Content
    constructor: (input...) ->
      super(input...)
      
      @base = commons.base @, "MediaContent"
      
    get: () ->
      super()
        .then( (file) =>
          max_size = 50
          MB = Math.pow(1024,2)
          
          stats = fs.statSync(file)
          if stats.isFile()
            if stats.size < max_size*MB
              Promise.resolve file
            else
              @base.rejectWithErrorString Promise.reject, __("filesize of \"%s\" is too large (%s MB). Max. allowed size is %s MB", file, stats.size/MB, max_size)
          else
            if stats.isDirectory()
              error = __("\"%s\" is a directory", file)
            else
              err = __("\"%s\" does not exist or is a *nix device", file)
            @base.rejectWithErrorString Promise.reject, error
        ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, err
        )
  
  class LocationContent extends Content
    constructor: (input...) ->
      super(input...)
      @base = commons.base @, "LocationContent"
      
    get: () ->
      super()
        .then( (gps) =>
          coord = gps.split(';')
          if (!isNaN(coord[0]) && coord[0].toString().indexOf('.') isnt -1) and (!isNaN(coord[1]) && coord[1].toString().indexOf('.') isnt -1)
            Promise.resolve coord
          else
            @base.rejectWithErrorString Promise.reject, __("'%s' and '%s' are not valid GPS coordinates", coord[0], coord[1])
        ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, err
        )
   
  
      
  class ContentFactory
    types = {
      text: TextContent
      video: MediaContent
      audio: MediaContent
      photo: MediaContent
      gps: LocationContent
      doc: MediaContent
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args...) ->
      return new types[type] args...
  
  return ContentFactory