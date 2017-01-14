pimatic-Telegram
=======================

Plugin to provide Pimatic integration with Telegram, the freely available messaging system available for a variety of platforms, such as mobiles, tablets and browsers, without additional cost
This plugin will allow you to send messages from Pimatic and allows Pimatic to receive remote requests which allows you to operate your pimatic system remotely in a safe manner. No inbound firewall ports need to be opened.

After installation the following actions and predicates will be made available in Pimatic:

Action Syntax: 

- send < text | video | audio | photo | gps > telegram  to [1stRecipient ... nthRecipient] <"text with $variables"  | "/local/path/with/$variables/to/file">

Specifying recipients is optional, if you do not provide recipients, a message will be sent to all defined recipients
Specifiying a message type is optional, when not specifying a type a text message is assumed

Precidate Syntax:

- telegram received "user-defined-keyword"

Defining rules with this predicate allows you to trigger a rule by sending a message ("user-defined-keyword" as per the example) via your telegram client
To use the predicates and be able to send requests to Pimatic, you need to define a new TelegramReceiverDevice, as well as set the Admin flag on authorized users in the Plugin config

- send actions to Pimatic from your client following the Pimatic rule action syntax, just as you would enter an action in the rule engine

Rule examples:

- 'send telegram KingOfMyCastle "ALERT! Pimatic detected movement in room: $room while nobody is home! You may want to check if someone is unexpectely making you a cup of tea"'
- 'send video telegram to KingOfMyCastle QueenofMyCastle "/home/pi/front_door_camera.mp4"'
- 'when telegram received "turn off heating" then set temp of Thermostat to 15'
- 'when it is 08:00 and $phone-child.location is not "School" send gps telegram to parent "$phone-child.latitude;$phone-child.longitude"

Messaging command examples:
- 'help' - lists available built-in commands and user-defined predicates
- 'list devices' - Summary list of all devices
- 'get device device_name | device_id' - get details on a device
- 'set temp of Thermostat to 15' - execute a device action using rule action syntax
- 'user defined keyword' - Triggers a defined rule with the "telegram received "user-defined-keyword" condition

Features:
========================
- Send text, audio, video, photo or location (GPS coord) messages to your (mobile) device equipped with the Telegram messaging client
- Messages may be of types: text, video, audio, or photo 
- Define multiple recipients in your Pimatic configuration via the user interface or config.json
- Enable / disable existing recipients
- Messages can be sent to one, more, or all defined recipients
- Messages and file paths may contain Pimatic variables
- Operate your Pimatic by triggering rules or sending device commands from your Telegram client
- Two factor authentication
  - Only known and authorized id's can send commands
  - Authentication is required before Pimatic accepts commands
  - User-configurable authentication timeout (ask password again after n minutes - default is 5 minutes)
- No inbound firewall ports need to be opened into Pimatic, as Pimatic initiates communication with the Telegram service (polling mechanism)


Known issues:
========================
- Rules according to the previous format (send telegram [recipient1 ...] "message") are NO LONGER supported. Upgrade your rules to the new format indicating the message type (e.g. send text telegram "message")
- "execute" cannot be used as a keyword, to prevent vulnerability exploitation. This is a security concern and will not likely be changed in the near future

Requirements
========================
- A Telegram client (Available for various mobile platforms, as well as webbased (www.telegram.org)
- A Telegram bot
- Obtain chatID's for all Telegram recipiets you would like to receive messages
- Allowed file formats depend on Telegram supported formats, .mp3 (audio), .mp4, .avi (video), .jpg and .png (photo) have been validated

Installation and Configuration:
========================
Please follow these steps to install and configure a working environment:

Obtain a Telegram client
=========================
- Go to the Apple store or Android Play store to install the client on your mobile and follow instructions

Creating a Telegram Bot
=========================
- With your Telegram client start a conversation with @BotFather
- Send a message: /newbot
- Follow the on-screen instructions
- When choosing a name for your bot, ensure the name ends in "bot", e.g. MyAwesomePimaticBot
- After completing the required steps, BotFather will provide a token (similar to this: 784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL)
- Make sure you copy this token, and keep it secret !

Obtain your chatID
========================
- With your Telegram client start a conversation with your bot (@MyAwesomePimaticBot)
- send a message, doesn't matter what the content is
- in your browser, type: https://api.telegram.org/bot784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL/getUpdates (replace the string after bot with your own token)
- in your browser you will see a JSON response similar to the below:
{"ok":true,"result":[{"update_id":123456789,
"message":{"message_id":1,"from":{"id":<this is the number you need!>,"first_name":"fname","username":"uname"},"chat":{"id":123456789,"first_name":"fname","username":"uname","type":"private"},"date":1481753058,"text":"Hello World!"}}]}
- Look for the number after "id", and save it.

Install the plugin
=======================
- Add pimatic-telegram to your pimatic config.json
- Check if the plugin has been activated. If not activate it
- Restart Pimatic

Configuration
=======================
To send messages from Pimatic:
In the plugin config page of Pimatic-Telegram enter the following information:
  - Enter the apiToken
  - Under recipients, click "Add" and add new recipients
   - For each recpient:
      - Enter a name friendly name (Alphanumeric)
      - Enter the corresponding ChatID in the appropriate fields
      - Check the "enabled" box, if the recipient is supposed to actually recieve messages
- Restart Pimatic
- Now you can use the action in rules to send messages to selected recipients in the Telegram app !

To send commands to Pimatic:
  - Define a new TelegramReceiverDevice
    - Make sure to change the default secret !
  - In the Plugin config, set selected users to be Admin
  - Optionally define or amend rules to include the "telegram received "keyword" predicate
  - Restart Pimatic
  - Send commands from Telegram to Pimatic, a good start is sending "help"

FAQ
======================
Please check the following first, as all similar issues have been solved so far by taking the below steps:

*I have installed Pimatic-Telegram, but no messages are sent, and no errors are logged. Whats wrong?

- Has the plugin been activated? Check in the section "Install the Plugin"
- Have you activated the intended recipient? Or has the enabled check box accidentally not been checked?
- Restart Pimatic, this is often forgotten after the installation and or configuration. 

*I have installed Pimatic-Telegram, but I cannot send instructions to Pimatic

- Have you defined a TelegramReceiverDevice and configured appropriately?
- Have you set the admin flag for the recipient sending commands and is the recipient enabled?
- Have you restarted Pimatic after making these configuration changes?

If you took these troubleshooting steps, you have probably rebooted Pimatic twice, once after installation, and once after configuration changes
