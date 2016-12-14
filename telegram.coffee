module.exports = (env) ->

  Promise = env.require 'bluebird'
  commons = require('pimatic-plugin-commons')(env)
  TelegramBotClient = require 'telegram-bot-client'
  M = env.matcher
    
  class Telegram extends env.plugins.Plugin
 
    init: (app, @framework, @config) =>
      @framework.ruleManager.addActionProvider(new TelegramActionProvider(@framework, @config))

  plugin = new Telegram()
  
  class TelegramActionProvider extends env.actions.ActionProvider

    constructor: (@framework, @config) ->

    parseAction: (input, context) =>
      retVal = null
      messageTokens = null
      fullMatch = no

      setCommand = (m, tokens) => messageTokens = tokens
      onEnd = => fullMatch = yes
      
      m = M(input, context)
        .match("send telegram ")
        .matchStringWithVars(setCommand)
      
      if m.hadMatch()
        match = m.getFullMatch()
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TelegramActionHandler(@framework, messageTokens, @config)
        }
      else
        return null

  class TelegramActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @messageTokens, @config) ->
      @base = commons.base @, "TelegramActionHandler"
      @host = @config.host
      @apiToken = @config.apiToken
      @userChatId = @config.userChatId
    
    executeAction: (simulate) =>
      @framework.variableManager.evaluateStringExpression(@messageTokens).then( (message) =>
        if simulate
          return __("would send telegram \"%s\"", message)
        else
          return new Promise((resolve, reject) =>
            client = new TelegramBotClient(@apiToken)    
            client.sendMessage(@userChatId, message).promise().then ((response) =>
              resolve __("Telegram \"%s\" to \"%s\" sent", response.result.text, response.result.chat.username)
            ), (err) =>
              @base.error __("Sending Telegram \"%s\" failed, reason: %s", message, err)
          )
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, error
      )
  return plugin