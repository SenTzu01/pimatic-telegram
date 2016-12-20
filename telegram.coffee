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
        
    sendMessage: (message, recipient) =>
      client = new TelegramBotClient(@apiToken)
      if recipient.enabled
        client.sendMessage(recipient.userChatId, message).promise().then ((response) =>
          env.logger.info __("Telegram \"%s\" to \"%s\" successfully sent", response.result.text, recipient.name)
          return Promise.resolve
        ), (err) =>
          env.logger.error __("Sending Telegram \"%s\" to \"%s\" failed, reason: %s", message, recipient.name, err)
          error = new Error(message)
          return Promise.reject error

    executeAction: (simulate) =>
      @framework.variableManager.evaluateStringExpression(@messageTokens).then( (message) =>
        if simulate
          return __("would send telegram \"%s\"", message)
        else
          return new Promise((resolve, reject) =>
            results = (@sendMessage(message, recipient) for recipient in @config.recipients)
            Promise.some(results, results.length).then( (result) =>
              resolve "Message sent to all recipients"
            ).catch(Promise.AggregateError, (err) =>
              @base.error "Message was NOT sent to all recipients"
            )
          )
      ).catch( (error) =>
        @base.rejectWithErrorString Promise.reject, error
      )

  return plugin