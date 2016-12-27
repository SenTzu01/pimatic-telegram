module.exports = (env) ->

  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require 'telegram-bot-client'
  M = env.matcher


  
  class Telegram extends env.plugins.Plugin
    
    migrateMainChatId: (@framework, @config) =>
      
      oldChatId = {
        name: "MainRecipient"
        enabled: true
        oldId: => 
          id = null
          if @config.hasOwnProperty('userChatId')
            id = @config.userChatId
          return id
        migrated: =>
          found = null
          found = recipient.userChatId for recipient in @config.recipients when recipient.userChatId is @config.userChatId
          return found
        migrate: =>
          if oldChatId.migrated() is null and oldChatId.oldId() isnt null
            env.logger.info "old userChatId: " + oldChatId.oldId() + " found, migrating..."
            oldChatId = {name: oldChatId.name, userChatId: oldChatId.oldId(), enabled: oldChatId.enabled}
            @config.recipients.push oldChatId
            delete @config.userChatId if @config.hasOwnProperty('userChatId')
            @framework.pluginManager.updatePluginConfig(@config.plugin, @config)
      }
      oldChatId.migrate()
      
    init: (app, @framework, @config) =>
      @migrateMainChatId(@framework, @config)
      @framework.ruleManager.addActionProvider(new TelegramActionProvider(@framework, @config))
    
    getConfig: =>
      return @config
      
  plugin = new Telegram()
  
  class TelegramActionProvider extends env.actions.ActionProvider
    
    constructor: (@framework, @config) ->
    
    parseAction: (input, context) =>
      match = null
      message = {
        type: "text"    # content type, e.g. video, photo, audio, text
        recipients: []  # array of intented recipients coming from rules
        content: null
      }
      
      # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
      @m1 = null
      @m2 = null
      m = M(input, context)
      m.or([
        ( (@m1) =>
          # Legacy Action maycher, remove in future version
          #
          # Action arguments: send telegram [1strecipient1 ... Nthrecipient] "message"
          @m1.match('send telegram ', (@m1) =>
            
            i = 0
            more = true
            all = @config.recipients.map( (r) => r.name + ' ')
            while more and i < all.length
              more = false if @m1.getRemainingInput().charAt(0) is '"' or null
          
              @m1.match(all, (@m1, r) => #get the recipients names
                recipient = r.trim()
                message.recipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient objects
              )
              i += 1
          )
          @m1.matchStringWithVars( (@m1, content) => #get the message content
            message.content = content
            match = @m1.getFullMatch()
          )
        ),
        ( (@m2) =>
          # New style Action matcher
          #
          # Action arguments: send [[telegram] | [text(default) | video | audio | photo] telegram to ]] [1strecipient1 ... Nthrecipient] "message | path | url"
          @m2.match('send ')
            .match(MessageFactory.getTypes().map( (t) => t + ' '), (@m2, type) => message.type = type.trim())
            .match('telegram ')
            .match('to ', optional: yes, (@m2) =>
            
              i = 0
              more = true
              all = @config.recipients.map( (r) => r.name + ' ')
              while more and i < all.length
                more = false if @m1.getRemainingInput().charAt(0) is '"' or null
                 
                @m2.match(all, (@m2, r) => #get the recipients names
                  recipient = r.trim()
                  message.recipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient object
                )
                i += 1
            )
          @m2.matchStringWithVars( (@m2, content) => #get the message content
            message.content = content
            match = @m2.getFullMatch()
          )
        )
      ])
      
      if match?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @config, message)
        }
      else    
        return null
  
  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @config, @message) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @recipients = if @message.recipients.length > 0 then @message.recipients else @config.recipients
      
    executeAction: (simulate) =>
      if simulate
        c = new Content(@framework, @message.content)
        return __("would send telegram \"%s\"", content.get())
      else
        results = null
        return new Promise((resolve, reject) =>
          new Content(@framework, @message.content).then( (c) =>
            @recipients.map( (r) => @sendMessage(r, c))
          ).then( (results) =>
            Promise.some(results, results.length).then( (result) =>
              resolve
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          )
        )
        
    sendMessage: (recipient, content) =>
      if recipient.enabled
        messageHandler = new MessageFactory(@message.type, @apiToken)
        return messageHandler.send(recipient, content)
  
  ###
  # BotClient SuperClass
  #
  # .prototype(token: string) => (botclient object)
  #
  ###
  class BotClient
    
    constructor: (@token) ->
      @client = new TelegramBotClient(@token)
  
  ###
  # TextMessage Class
  #
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ####
  class TextMessage extends BotClient
  
    send: (@recipient, @content) =>
        @client.sendMessage(@recipient.userChatId, @content.get()).promise().then ((response) =>
          return Promise.resolve env.logger.info __("Telegram text \"%s\" to \"%s\" successfully sent", @content.get(), @recipient.name)
        ), (err) =>
          return Promise.reject env.logger.error __("Sending Telegram text \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.name, err)
      
  ###
  # VideoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends BotClient
    
    send: (@recipient, @content) =>
        @client.sendVideo(@recipient.userChatId, @content.get()).promise().then ((response) =>
          return Promise.resolve env.logger.info __("Telegram video \"%s\" to \"%s\" successfully sent", @content.get(), @recipient.name)
        ), (err) =>
          return Promise.reject env.logger.error __("Sending Telegram video \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.name, err)
  
  ###
  # AudioMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class AudioMessage extends BotClient
    
    send: (@recipient, @content) =>
        @client.sendAudio(@recipient.userChatId, @content.get()).promise().then ((response) =>
          return Promise.resolve env.logger.info __("Telegram audio \"%s\" to \"%s\" successfully sent", @content.get(), @recipient.name)
        ), (err) =>
          return Promise.reject env.logger.error __("Sending Telegram audio \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.name, err)
  ###
  # PhotoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class PhotoMessage extends BotClient
    
    send: (@recipient, @content) =>
        @client.sendPhoto(@recipient.userChatId, @content.get()).promise().then ((response) =>
          return Promise.resolve env.logger.info __("Telegram photo \"%s\" to \"%s\" successfully sent", @content.get(), @recipient.userChatId)
        ), (err) =>
          return Promise.reject env.logger.error __("Sending photo text \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.userChatId, err)
  
  ###
  #
  # MessageFactory FactoryClass
  #
  # .getTypes() => (contentTypes: array)
  # .getInstance(type: string, opts: )
  #
  ###
  class MessageFactory
    types = {
      text: TextMessage
      video: VideoMessage
      audio: AudioMessage
      photo: PhotoMessage
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      return new types[type] args
  
  ###
  #  Recipient Class
  #
  # .prototype(name: string, id: string, enabled: bool) => (recipient object)
  # .getId() => (id:string)
  # .getName() => (name:string)
  # .isEnabled() => (enabled: bool)
  #
  ###
  class Recipient
    
    constructor: (@name, @id, @enabled = false) ->
      return new Promise((resolve, reject) =>
        resolve @ 
      ).catch( (err) =>
        reject "Failed to return Content object"
      )
    getId: () =>
      env.logger.info "@id: ", @id
      return @id
      
    getName: () =>
      env.logger.info "@name: ", @name
      return @name
        
    isEnabled: () =>
      env.logger.info "@enabled: ", @enabled
      return @enabled
  
  ###
  #  Content Class
  #
  # .get() => (content:string)
  # .parse(content: string) => (Promise(resolve, reject)
  #
  ###
  class Content
    
    constructor: (@framework, @input) ->
      return new Promise((resolve, reject) =>
        @base = commons.base @, "TelegramActionHandler"
        @output = "not set"
        @parse(@input)
        resolve @ 
      ).catch( (err) =>
        reject "Failed to return Content object"
      )
    get: () =>
      return @output
      
    parse: (@input) =>
        @framework.variableManager.evaluateStringExpression(@input).then( (message) =>
          env.logger.info "message: '", message, "'"
          @output = message
          return "Message parsed with success"
        ).catch( (error) =>
          @base.rejectWithErrorString Promise.reject, error
        )
      
  return plugin