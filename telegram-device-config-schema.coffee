module.exports = {
  title: "Telegram device config schemas"
  TelegramReceiverDevice: {
    title: "Telegram Receiver configuration options"
    type: "object"
    properties:
      disable2FA:
        description: "Setting disable2FA to Yes, will allow users to send requests without providing a password. This lowers security!"
        type: "boolean"
        default: false
      secret:
        description: "Passcode to provide before requests are accepted"
        type: "string"
        default: "change_me_now!"
      auth_timeout:
        description: "Time after which passcode needs to be re-entered (in minutes)"
        type: "number"
        default: 5
      stateStartup:
        description: "Start Telegram Listener at Pimatic start?"
        type: "boolean"
        default: true
      confirmRuleTrigger:
        description: "Should the receiver send confirmation upon executing rule actions?"
        type: "boolean"
        default: true
      confirmDeviceAction:
        description: "Should the receiver send confirmation upon executing device actions?"
        type: "boolean"
        default: true
      interval:
        description: "How often to check for new requests (in ms)"
        type: "number"
        default: 1000
      timeout:
        description: "Message polling timout (0 - short polling)"
        type: "number"
        default: 0
      limit:
        description: "Number of new requests to be retrieved"
        type: "number"
        default: 10
      retryTimeout:
        description: "Reconnect timeout (in ms)"
        type: "number"
        default: 5000
  }
}