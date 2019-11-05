pimatic-Telegram
=======================

Pimatic plugin to provide bi-directional integration with Telegram, the free messaging system for mobile and desktop devices

### Features
- Send messages from Pimatic to your (mobile) device equipped with the Telegram messaging client
- Limited HTML markup in messages supported such as \<b\> \<i\> and \<a href=...\> tags as per Telegram API
- Send device and rule requests to Pimatic from your Telegram client
- Rule requests may contain variables to be used in rule actions
- Support for Text / Video / Audio / Image / GPS Location Message types (gps location shows up as a map in the client)
- Support for sending messages to all enabled or multiple individual recipients
- Enable / disable recipients for receiving messages and / or sending requests from a messaging client
- Messages and file paths may contain Pimatic variables
- Two factor authentication (Trusted sender list maintained in Pimatic, with session password)
- User-configurable authentication timeout
- Polling mechanism prevents exposing your Pimatic environment
- Allowed file formats depend on Telegram supported formats, .mp3 (audio), .mp4, .avi (video), .jpg and .png (photo) have been validated (Max. allowed file size for media and doc types is 50MB, set by Telegram.org)

### Rule syntax and examples: 
<b>send < text | video | audio | photo | doc | gps > telegram to [sender | recipient1 recipient2 ... recipientn ] < "text with $variables"  | "/local/path/with/$variables/to/file" | "$latitude;$longitude" ></b><br/>
and / or:<br/>
<b>telegram received "user-defined-keyword"</b><br/>

- send text telegram to sender "reply only to user having send request" <i>Can only be used in combination with "telegram received... rule predicate"</i>
- send text telegram to "\<b\>ALERT!\</b\> Pimatic detected movement in room: \<i\>$room\</i\> while nobody is home! Is someone unexpectedly making you a cup of tea?"<br/>
- send video telegram to Owner1 Owner2 "/home/pi/front_door_camera.mp4"<br/>
- when it is 08:00 and $phone-child.location is not "School" send gps telegram to Parent1 Parent2 "$phone-child.latitude;$phone-child.longitude"<br/>
- when telegram received "turn off heating" then set temp of Thermostat to 15<br/>
- when telegram received "myscript" with arguments then execute "myscript \\$var1 \\$var2"<br/>

<i>If you do not provide recipients, a message will be sent to all enabled recipients</i><br>
 
### Requests sent from messaging client to Pimatic:
<b>help</b> - lists available built-in commands and user-defined predicates</br>
<b>list devices</b> - Summary list of all devices</br>
<b>get device device_name | device_id</b> - get details on a device</br>
<b>set temp of Thermostat to 15</b> - execute a device action using rule action syntax</br>
<b>user defined keyword</b> - Triggers a defined rule with the "telegram received 'user-defined-keyword'" condition</br>
<b>user defined keyword \<var1\> \<varN\></b> - Triggers a defined rule with the "telegram received 'user-defined-keyword' with arguments" condition</br>


Preinstallation Requirements
========================
- A Telegram client (www.telegram.org)
- A Telegram bot
- Obtain chatID's for all Telegram recipiets you would like to receive messages


Installation and Configuration:
========================

### Obtain a Telegram client

- Go to the Apple store or Android Play store to install the client on your mobile and follow instructions

### Create a Telegram Bot

- With your Telegram client start a conversation with @BotFather
- Send a message: <b>/newbot</b>
- Follow the on-screen instructions
- When choosing a name for your bot, ensure the name ends in "bot", e.g. MyAwesomePimaticBot
- After completing the required steps, BotFather will provide a token (similar to this: <b>784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL</b>)
- <b>Make sure you copy this token, and keep it secret !</b>

### Obtain your chatID

- With your Telegram client start a conversation with your bot (@MyAwesomePimaticBot)
- send a message, doesn't matter what the content is
- in your browser, type: https://api.telegram.org/bot784324329:EETRNJU3jQEGWQdjNv3llb4bnDSDREGuuuL/getUpdates (replace the string after bot with your own token)
- in your browser you will see a JSON response similar to the below:
````json
{
  "ok":true,
  "result":
  [{
    "update_id":100,
    "message":{
      "message_id":12,
      "from":
      {
        "id": "<this_is_the_number_you_need!>",
        "first_name":"fname","username":"uname"
      },
      "chat":
      {
        "id":123456789,
        "first_name":"fname",
        "username":"uname",
        "type":"private"
      },
      "date":1481753058,
      "text":"Hello World!"
    }
  }]
}
````
- Look for the number after "id", and save it
- Repeat for each recipient you want to register in Pimatic

### Install the Plugin (required for using the send telegram functions)

- Install Pimatic-Telegram via the frontend (preferred) and check if it has been activated. 
- Add the API token in the designated field, and add recipients as required (Friendly name, chat ID, enabled flag)

Alternatively add it to the Plugin section of your config.json:
````json
{
  "plugin": "telegram",
  "apiToken": "<bot api_token from previous step>",
  "active": true,
  "recipients": [
    {
      "name": "FriendlyName",
      "userChatId": "<user_id from previous step>",
      "enabled": true,
      "admin": false 
    }]
}
````
<i> You can specify multiple recipients. Enabled should be set to true for a recipient to receive messages</i>
- Check if the plugin has been activated. If not activate it
- Restart Pimatic

### Install a Telegram Receiver device (required to send client requests to Pimatic, and enable the <i>telegram received</i> rule predicate)

- Define a new TelegramReceiverDevice via the frontend (preferred)
  - Make sure to change the default secret !
- To allow users to send requests to Pimatic, set their Admin flag to enabled in the frontend or in config.json
````json
"recipients": [
  {
    "name": "FriendlyName",
    "userChatId": "<user_id from previous step>",
    "enabled": true,
    "admin": true 
  }
````
- Restart Pimatic
- Send commands from Telegram to Pimatic, a good start is sending "help"

Alternatively add the device directly to the Devices section your config.json:
````json
{
  "secret": "change_me_now!",
  "auth_timeout": 5,
  "id": "telegram-receiver",
  "name": "Telegram Receiver",
  "class": "TelegramReceiverDevice"
}
````

### Known issues:

- "execute" cannot be used as a keyword, to prevent vulnerability exploitation. This is a security concern and will not likely be changed in the near future

### FAQ

Please check the following first, as all similar issues have been solved so far by taking the below steps:

<b>I have installed Pimatic-Telegram, but no messages are sent, and no errors are logged. Whats wrong?</b>

- Has the plugin been activated? Check in the section "Install the Plugin"
- Have you activated the intended recipient? Or has the enabled check box accidentally not been checked?
- Restart Pimatic, this is often forgotten after the installation and or configuration. 

<b>I have installed Pimatic-Telegram, but I cannot send instructions to Pimatic</b>

- Have you defined a TelegramReceiverDevice and configured appropriately?
- Have you set the admin flag for the recipient sending commands and is the recipient enabled?
- Have you restarted Pimatic after making these configuration changes?

If you took these troubleshooting steps, you have probably rebooted Pimatic twice, once after installation, and once after configuration changes
