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
  }
}