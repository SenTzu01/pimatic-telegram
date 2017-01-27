module.exports = (env) ->
  
  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  
  class Message
  
    constructor: (options) ->
      @recipients = []
      @content = null
      @client = null
      @base = commons.base @, "Message"
      
    
    processResult: (method, message, recipient, log  = false) =>
        method.then( (response) =>
          log_msg = __("[Message] Sending Telegram \"%s\" to %s: success", message, recipient)
          if !log
            env.logger.debug log_msg
          else
            env.logger.info log_msg
          return Promise.resolve
        ).catch( (err) =>
          env.logger.info err
          env.logger.error __("[Message] Sending Telegram \"%s\" to %s: failed; reason: %s", message, recipient, err.description)
          return Promise.reject err
          
        )
    
    addRecipient: (recipient) =>
      @recipients.push recipient
    
    addContent: (content) =>
      @content = content
    
    addSingleRecipient: (recipient) ->
      @recipients = []
      @addRecipient(recipient)
      
  class TextMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "TextMessage"
      
    send: (@client, log) =>
      @content.get().then( (message) =>
        @recipients.map( (r) =>
          Promise.all(@sendMessageParts(message, r, log)).then( (result) =>
            return Promise.resolve
          ).catch( (err) =>
            return Promise.reject err
          )
        )   
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, "Unable to get content"
      )
    
    sendMessageParts: (message, recipient, log) =>
      parts = message.match(/[\s\S]{1,2048}/g)
      return parts.map( (part) => @processResult(@client.sendMessage(recipient.getId(), part), part, recipient.getName(), log) )
      
  class VideoMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "VideoMessage"
      
    send: (@client, log) =>
      @content.get().then( (file) =>
        return @recipients.map( (r) => @processResult(@client.sendVideo(r.getId(), file), file, r.getName(), log))
      ).catch( (err) =>
        @base.rejectWithErrorString Promise.reject, "Unable to send Video file"
      )
      
  class AudioMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "AudioMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
          return @recipients.map( (r) => @processResult(@client.sendAudio(r.getId(), file), file, r.getName(), log))
        ).catch((err) =>
          @base.rejectWithErrorString Promise.reject, "Unable to send Audio file"
        )
      
  class PhotoMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "PhotoMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
            return @recipients.map( (r) => @processResult(@client.sendPhoto(r.getId(), file), r.getName(), log))
        ).catch( (err) =>
            @base.rejectWithErrorString Promise.reject, "Unable to send Image file"
        )
  
  class DocumentMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "DocumentMessage"
      
    send: (@client, log) =>
      @content.get()
        .then( (file) =>
            return @recipients.map( (r) => @processResult(@client.sendDocument(r.getId(), file), r.getName(), log))
        ).catch( (err) =>
            @base.rejectWithErrorString Promise.reject, "Unable to send file"
        )
  
  class LocationMessage extends Message
    constructor: (options) ->
      super(options)
      @base = commons.base @, "LocationMessage"
      
    send: (@client) =>
      @content.get().then( (gps) =>
        return @recipients.map( (r) => @processResult(@client.sendLocation(r.getId(), [gps[0], gps[1]]), gps, r.getName()))
      ).catch( (err) =>
          @base.rejectWithErrorString Promise.reject, "Unable to send Location coordinates"
      )
  
  class MessageFactory
    types = {
      text: TextMessage
      video: VideoMessage
      audio: AudioMessage
      photo: PhotoMessage
      gps: LocationMessage
      doc: DocumentMessage
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
      
  return MessageFactory