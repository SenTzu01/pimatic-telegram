module.exports = {
  title: "Telegram device config schemas"
  TelegramReceiverDevice: {
    title: "Telegram Receiver configuration options"
    type: "object"
    properties:
      secret:
        description: "Passcode to provide before requests are accepted"
        type: "string"
        default: "change_me_now!"
      interval:
        description: "How often to check for new requests (in ms)"
        type: "number"
        default: 1000
      timeout:
        description: "Update polling timout (0 - short polling"
        type: "number"
        default: 0
      limit:
        description: "Number of new requests to be retrieved"
        type: "number"
        default: 100
      retryTimeout:
        description: "Reconnect timeout (in ms)"
        type: "number"
        default: 5000
      commands:
        description: "List of allowed commands"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          required: ["name", "request", "variable", "value"]
          properties:
            name:
              description: "Friendly name for this request"
              type: "string"
            request:
              description: "Bot (slash) request to accept"
              type: "string"
            variable:
              description: "Pimatic variable to set when receiving the request"
              type: "string"
            value:
              description: "Value to which the variable is set when receiving the request. Expression?"
              type: "string"
            enabled:
              description: "Enable / Disable this request definition"
              type: "boolean"
              default: yes
            label:
              description: "Custom label for the frontend"
              type: "string"
  }
}