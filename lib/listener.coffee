module.exports = (env) ->
  
  BotClient = require('./botclient')(env)
  MessageFactory = require('./messages')(env)
  ContentFactory = require('./content')(env)
  
  class Listener
  
    constructor: (@config, @TelegramPlugin) ->
      @token = @TelegramPlugin.getToken()
      @devices = @TelegramPlugin.getDevices()
      @sender = (id) -> @TelegramPlugin.getSender(id)
      @actions = -> @TelegramPlugin.getActionProviders()
      @client = null
      @authenticated = []
      @requests = [{
          request: "help"
          type: "base"
          action: -> return null
          protected: false
          response: (msg) =>
            text = "Default commands: \n"
            for req in @requests
              if req.type is "base"
                text += "\t" + req.request
                if req.request is "get device"
                  text += " <device name | device id>"
                text += "\n"
            text += "\nRule commands: \n"
            for req in @requests
              if req.type is "rule"
                text += "\t" + req.request + "\n"
            return text
        },
        {
          request: "execute", 
          action: => 
            env.logger.warn "'execute' request received; This is not allowed for security reasons" # It's a trap !!
            return null
          protected: false
          response: (msg) ->
            text = "request 'execute' received; This is not allowed for security reasons"
            return text
        },
        {
          request: "list devices"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) =>
            text = 'Devices :\n'
            for dev in @devices
              text += '\tName: ' + dev.name + "\tID: " + dev.id + "\n\n"
            return text
        },
        {
          request: "get device"
          type: "base"
          action: -> return null
          protected: true
          response: (msg) => 
            obj = msg.split("device", 4)
            for dev in @devices
              if ( obj[1].substring(1) == dev.id.toLowerCase() ) or ( obj[1].substring(1) == dev.name.toLowerCase() )
                text = 'Name: ' + dev.name + " \tID: " + dev.id + " \tType: " +  dev.constructor.name + "\n"
                for name of dev.attributes
                  text += '\t\t' + name.charAt(0).toUpperCase() + name.slice(1) + ": " + dev.getLastAttributeValue(name) + "\n\n"
                return text
            return "device not found"
        }]
      
    start: (@client) =>
      env.logger.info "Starting Telegram listener"
      @client.connect()
      @enableRequests()
    
    stop: (@client) =>
      env.logger.info "Stopping Telegram listener"
      @authenticated = []
      @client.disconnect()
      
    enableRequests: () =>
      
      @client.on('/*', (msg) =>
        env.logger.debug "Bot command received: ", msg
        client = new BotClient({token: @token})
        response = new MessageFactory("text")
        response.addRecipient(@sender(msg.from.id.toString()))
        response.addContent(new ContentFactory("text", 'Bot commands (/<cmd>) are not implemented', @TelegramPlugin))
        client.sendMessage(response)
        return true
      )
      
      @client.on('text', (msg) =>

        return if msg.text.charAt(0) is '/'
        env.logger.debug "Request '", msg.text, "' received, processing..."
        sender = @sender(msg.from.id.toString())
        
        # auth logic
        if !sender.isAdmin() # Lord Vader force-chokes you !!
          env.logger.warn "auth_denied", sender.getName() + " is not authorized. Terminating request"
          return
        
        date = new Date()
        client = new BotClient({token: @token})
        response = new MessageFactory("text")
        response.addRecipient(sender)
        
        if @config.secret is msg.text # Face Vader you must!
          @authenticated.push {id: sender.getId(), time: date.getTime()}
          response.addContent(new ContentFactory("text", "Passcode correct, timeout set to " + @config.auth_timeout + " minutes. You can now issue requests", @TelegramPlugin))
          client.sendMessage(response)
          env.logger.info sender.getName() + " successfully authenticated"
          return
        
        for auth in @authenticated
          if auth.id is sender.getId()
            if auth.time < (date.getTime()-(@config.auth_timeout*60000)) # You were carbon frozen for too long, Solo! Solo! Too Nakma Noya Solo!
              sender.setAuthenticated(false)
            else
              sender.setAuthenticated(true)
        
        
        request = msg.text.toLowerCase()
        match = false
        # command logic
        if sender.isAuthenticated()  # May the force be with you
          env.logger.info "Request '" + request + "' received from " + sender.getName()
          for req in @requests
            if req.request.toLowerCase() is request.slice(0, req.request.length) # test request against base commands and 'receive "command"' predicate in ruleset
              req.action()
              if req.type is "base" or @config.confirmRuleTrigger
                response.addContent(new ContentFactory("text", req.response(request), @TelegramPlugin))
                client.sendMessage(response)
              match = true
              break
          
          if !match
            for act in @actions
              context = createDummyParseContext()
              han = act.parseAction(request, context) # test if request is a valid action, e.g. "turn on switch-room1"
              if han?
                han.actionHandler.executeAction()
                if @instance.config.confirmDeviceAction
                  response.addContent(new ContentFactory("text", "Request '" + request + "' executed", @TelegramPlugin))
                  client.sendMessage(response)
                match = true
                break
          
          if !match
            response.addContent(new ContentFactory("text", "'" + request + "' is not a valid request", @TelegramPlugin))
            client.sendMessage(response)
            return
          return
        else # Vader face you must
          response.addContent(new ContentFactory("text", "Please provide the passcode first and reissue your request after", @TelegramPlugin))
          client.sendMessage(response)
          return
      )
      
    createDummyParseContext = ->
      variables = {}
      functions = {}
      return M.createParseContext(variables, functions)
    
    requestAdd: (req) =>
      if !@requestIsRegistered(req)
        obj = {
          request: req.getCommand()
          action: (msg) => req.emit('change', 'event')
          protected: true
          type: "rule"
          response: (msg) => return "Rule condition '" + obj.request + "' triggered"
        }
        @requests.push obj
        env.logger.info "Listener enabled ruleset command: '", obj.request, "'"
          
    requestChange: (req) =>
      @requestDelete(req)
      @requestAdd(req)
      
    requestDelete: (req) =>
      i = -1 # additional iterator needed as array.indexOf(elem) does not work on array of objects
      for obj in @requests
        i++
        if obj.request is req.getCommand()
          @requests.splice(i,1)
          break
      env.logger.info "Listener disabled ruleset command: '", req.getCommand(), "' "
      
    requestIsRegistered: (req) =>
      reistered = false
      for obj in @requests
        if obj.request is req.getCommand()
          registered = true
          break
      return registered
      
  return Listener