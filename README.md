# Sourcemod Discord Chat Relay
Discord chat relay for sourcemod servers.

Requirements:
------
* [Discord API](https://github.com/Cruze03/sourcemod-discord/)
  * [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)
  * [smjansson](https://forums.alliedmods.net/showthread.php?t=184604)
* [Socket](https://forums.alliedmods.net/showthread.php?t=67640)
* (for compilation)[ripext](https://forums.alliedmods.net/showthread.php?t=298024)
* (for compilation)[morecolors.inc](https://forums.alliedmods.net/showthread.php?t=185016)

Note: You'll need a discord app with bot. [How to create](https://github.com/Deathknife/sourcemod-discord/wiki/Setting-up-a-Bot-Account)

Installation:
------
1. Put the `dcr-server.smx` in your servers `addons/sourcemod/plugins` directory.
2. For the `dcr-server.smx`, you have to copy the `dcr.cfg` to `addons/sourcemod/configs` and replace `<insert-bot-token>` with your bot token
3. Start the server once and modify the now created `cfg/sourcemod/discord-chat-relay-server.cfg`. To get the Channel id, enable Developer Mode in Discords `Appearance -> Advanced` settings and right click the channel you want to get the id from. Select `Copy ID` to copy the ID.
4. Restart the server.

How it works:
------
dcr-server connects to discord, then if you send a message on Discord, the gameserver will retrieve it and send it to the server chat. If you send a message in the gameserver, it'll send the message to Discord.
