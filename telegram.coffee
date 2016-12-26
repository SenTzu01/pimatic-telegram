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
      #messageTokens = null
      match = null
      @allRecipients = []
      @msgRecipients = []
      @more = true
      
      @message = {
        type: "text"    # content type, e.g. video, photo, audio, text
        recipients: []  # array of intented recipients coming from rules
        content: null
      }
      
      # final state: send [text | video | audio | photo] telegram [[to] recipient1 ... recipientn] "message | path | url" [[to] recipient1 ... recipient] => defaults to text
      # current state: send telegram [text | video] [recipient1 ... recipientn] "message | path | url"
      
      @m = M(input, context).match('send telegram ')
      @m.match(MessageFactory.getTypes().map( (t) => t + " "), optional: yes, (@m, content) => # add content type, eg video, photo, text, if none provided default to text
        env.logger.info "'",content,"'"
        @message.type = content.trim() if content isnt null
        
      )
      
      @allRecipients.push (recipient.name + " ") for recipient in @config.recipients
      i = 0
      while @more and i < @allRecipients.length # i needed to avoid lockup while editing existing rules, Pimatic bug?
        next = if @m.getRemainingInput() isnt null then @m.getRemainingInput().charAt(0) else null
        @more = false if next is '"' or null
        
        @m.match(@allRecipients, (@m, r) => #get the recipients names
          recipient = r.trim()
          @msgRecipients.push obj for obj in @config.recipients when obj.name is recipient # build array of recipient objects 
        )
        i += 1
      
      @m.matchStringWithVars( (@m, message) => #get the message content
        @message.content = message
        match = @m.getFullMatch()
      )
      
      if match?
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, @config, @message)
        }
      else    
        return null
  
  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @config, @message) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @recipients = @config.recipients if @message.recipients.length < 1
    
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
            #env.logger.info "5. results: ", results
            Promise.some(results, results.length).then( (result) =>
              resolve "6. Message sent to all recipients"
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          )
        )
        
    sendMessage: (recipient, content) =>
        type = new MessageFactory(@message.type, @apiToken)
        return type.send(recipient, content)
  
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
      if @recipient.enabled
        #env.logger.info "2. @recipient is enabled, continue..."
        #env.logger.info "3. @recipinet.userChatId: ", @recipient.userChatId, " @content: ", @content.get()
        
        @client.sendMessage(@recipient.userChatId, @content.get()).promise().then ((response) =>
          #env.logger.info __("4. Telegram \"%s\" to \"%s\" successfully sent", response.result.text, @recipient.name)
          return Promise.resolve env.logger.info __("Telegram \"%s\" to \"%s\" successfully sent", response.result.text, @recipient.name)
        ), (err) =>
          
          error = new Error(@content.get())
          return Promise.reject env.logger.error __("Sending Telegram \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.name, err)
      #else
      #  env.logger.info "recipient is disabled"
      #  resolve "Message was not sent to user: ", @recipient.name, " reason: recipient disabled"
      
  ###
  # VideoMessage Class
  #  
  # .send (recipient: Recipient object, message: Content object) => (Promise.reject, Promise.resolve)
  #
  ###
  class VideoMessage extends BotClient
    
    send: (@recipient, @content) =>
      if @recipient.enabled
        #env.logger.info "2. @recipient is enabled, continue..."
        #env.logger.info "3. @recipinet.userChatId: ", @recipient.userChatId, " @content: ", @content.get()
        
        @client.sendVideo(@recipient.userChatId, @content.get()).promise().then ((response) =>
          #env.logger.info __("4. Telegram \"%s\" to \"%s\" successfully sent", response.result.text, @recipient.name)
          return Promise.resolve env.logger.info __("Telegram \"%s\" to \"%s\" successfully sent", response.result.text, @recipient.name)
        ), (err) =>
          
          error = new Error(@content.get())
          return Promise.reject env.logger.error __("Sending Telegram \"%s\" to \"%s\" failed, reason: %s", @content.get(), @recipient.name, err)
      #else
      #  env.logger.info "recipient is disabled"
      #  resolve "Message was not sent to user: ", @recipient.name, " reason: recipient disabled"
  
  
  
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
    }
    
    @getTypes: -> return Object.keys(types)
    
    constructor: (type, args) ->
      #env.logger.info classes
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
    
    constructor: (@name, @id, @enabled) ->
      #env.logger.info "In Recipient class, @name: ", name, " @id: ", @id, " @enabled: ", @enabled
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
        #env.logger.info "1. in Content cnstructor, @input: ", @input
        @base = commons.base @, "TelegramActionHandler"
        @output = " not set"
        @parse(@input)
        resolve @ 
      ).catch( (err) =>
        reject "Failed to return Content object"
      )
    get: () =>
      #env.logger.info "@output: ", @output
      return @output
      
      
    parse: (input) =>
      #return new Promise((resolve, reject) =>
        #env.logger.info "right before parse, input: ", input
        @framework.variableManager.evaluateStringExpression(input).then( (message) =>
          #env.logger.info "message: ", message
          @output = message
          #env.logger.info "Message parsed with success"
          return "Message parsed with success"
        ).catch( (error) =>
          #env.logger.info "Message parse failure"
          @base.rejectWithErrorString Promise.reject, error
        )
      #)
      
  return plugin