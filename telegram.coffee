module.exports = (env) ->

  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require 'telegram-bot-client'

  fs = require('fs')
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
          if oldChatId.oldId() isnt null
            if oldChatId.migrated() is null
              env.logger.info "old userChatId: " + oldChatId.oldId() + " found, migrating..."
              oldChatId = {name: oldChatId.name, userChatId: oldChatId.oldId(), enabled: oldChatId.enabled}
              @config.recipients.push oldChatId
            delete @config.userChatId

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
        type: "text"
        recipients: []
        content: null
      }
      
      @m1 = null
      @m2 = null
      m = M(input, context)
      m.or([
        ( (@m1) =>
          # Legacy Action matcher, remove in future version
          #
          # Action arguments: send telegram [1strecipient1 ... Nthrecipient] "message"
          @m1.match('send telegram ', (@m1) =>
            
            i = 0
            more = true
            all = @config.recipients.map( (r) => r.name + ' ')
            while more and i < all.length
              more = false if @m1.getRemainingInput().charAt(0) is '"' or null
          
              @m1.match(all, (@m1, r) =>
                recipient = r.trim()
                message.recipients.push obj for obj in @config.recipients when obj.name is recipient
              )
              i += 1
          )
          @m1.matchStringWithVars( (@m1, content) =>
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

                @m2.match(all, (@m2, r) =>
                  recipient = r.trim()
                  message.recipients.push obj for obj in @config.recipients when obj.name is recipient
                )
                i += 1
            )
          @m2.matchStringWithVars( (@m2, content) =>
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
          c = new Content(@framework, @message.content)
          results = @recipients.map( (r) => @sendMessage(r, c))
          Promise.some(results, results.length).then( (result) =>
            resolve
          ).catch(Promise.AggregateError, (err) =>
            @base.error "Message was NOT sent to all recipients"
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
      @base = commons.base @, "TelegramActionHandler"
  ###
  # TextMessage Class
  #
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ####
  class Message extends BotClient

    processResult: (method) =>
        method.promise().then ((response) =>
          env.logger.info __("Telegram \"%s\" to %s successfully sent", @content, @recipient.name)
          return Promise.resolve 
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to %s failed, reason: %s", @content, @recipient.name, err)
          return Promise.reject 
    
  ###
  # TextMessage Class
  #
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ####
  class TextMessage extends Message
      
    send: (@recipient, @content) =>
      @content.get().then( (message) =>
        @content = message
        @processResult(@client.sendMessage(@recipient.userChatId, message))
      )
     
  ###
  # VideoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends Message
      
    send: (@recipient, @content) =>
      @content.get().then( (file) =>
        @content = file
        if fs.existsSync(file)
          @processResult(@client.sendVideo(@recipient.userChatId, file))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file) 
      )
  ###
  # AudioMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class AudioMessage extends Message
    
    send: (@recipient, @content) =>
      @content.get().then( (file) => 
        @content = file
        if fs.existsSync(file)
          @processResult(@client.sendAudio(@recipient.userChatId, file))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
      )
  ###
  # PhotoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class PhotoMessage extends Message
    
    send: (@recipient, @content) =>
      @content.get().then( (file) =>
        @content = file
        if fs.existsSync(file)
          @processResult(@client.sendPhoto(@recipient.userChatId, file))
        else
          @base.rejectWithErrorString Promise.reject, __("Cannot send media via telegram - File: \"%s\" does not exist", file)
      )
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
        @base = commons.base @, "TelegramActionHandler"
        
    get: () =>
      return new Promise((resolve, reject) =>
        @framework.variableManager.evaluateStringExpression(@input).then( (content) =>
          resolve content
        ).catch( (error) =>
          reject error
        )
      ).catch((error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
        

  return plugin